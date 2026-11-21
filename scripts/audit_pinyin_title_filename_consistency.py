from __future__ import annotations

import argparse
import random
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from mutagen import File as mutagen_file
from mutagen.id3 import ID3, ID3NoHeaderError


SUPPORTED_SUFFIXES = {".mp3", ".flac", ".m4a", ".ogg", ".wma", ".aiff", ".aac", ".wav"}
MULTI_SPACE_RE = re.compile(r"\s+")
LEADING_TRACK_RE = re.compile(r"^\s*\d{1,3}[\s._\-]+")
SPLIT_ARTIST_RE = re.compile(r"\s+-\s+|\s+_\s+|\s+／\s+|\s+/\s+")


@dataclass(frozen=True)
class SampleRow:
    path: Path
    file_name: str
    file_title: str
    metadata_title: str
    matches: bool
    reason: str


def clean_text(value: str | None) -> str:
    if value is None:
        return ""
    text = unicodedata.normalize("NFKC", value)
    text = text.replace("_", " ")
    text = MULTI_SPACE_RE.sub(" ", text).strip()
    return text


def canonicalize_title(value: str) -> str:
    text = clean_text(value).casefold()
    text = LEADING_TRACK_RE.sub("", text)
    text = re.sub(r"[\[\](){}【】『』《》]", " ", text)
    text = re.sub(r"[^\w\u3400-\u4dbf\u4e00-\u9fff]+", " ", text)
    text = MULTI_SPACE_RE.sub(" ", text).strip()
    return text


def canonicalize_filename_stem(stem: str) -> list[str]:
    cleaned = clean_text(stem)
    parts = [cleaned]
    split_parts = [part.strip() for part in SPLIT_ARTIST_RE.split(cleaned) if part.strip()]
    if len(split_parts) > 1:
        parts.extend(split_parts)
        parts.append(split_parts[-1])
    normalized: list[str] = []
    seen: set[str] = set()
    for part in parts:
        canonical = canonicalize_title(part)
        if canonical and canonical not in seen:
            seen.add(canonical)
            normalized.append(canonical)
    return normalized


def read_metadata_title(path: Path) -> str:
    if path.suffix.lower() == ".mp3":
        return read_mp3_title(path)
    audio = mutagen_file(path, easy=True)
    if audio is None:
        return ""
    tags = getattr(audio, "tags", None) or {}
    title = tags.get("title")
    if isinstance(title, list) and title:
        return clean_text(str(title[0]))
    if isinstance(title, str):
        return clean_text(title)
    return ""


def read_mp3_title(path: Path) -> str:
    try:
        tags = ID3(path)
    except ID3NoHeaderError:
        return ""
    frame = tags.get("TIT2")
    if frame is None:
        return ""
    text = getattr(frame, "text", None)
    if isinstance(text, list) and text:
        return clean_text(str(text[0]))
    if isinstance(text, str):
        return clean_text(text)
    return clean_text(str(frame))


def collect_audio_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES:
            files.append(path)
    return sorted(files)


def compare_title_with_filename(path: Path) -> SampleRow:
    file_title = clean_text(path.stem)
    metadata_title = read_metadata_title(path)
    if not metadata_title:
        return SampleRow(
            path=path,
            file_name=path.name,
            file_title=file_title,
            metadata_title="",
            matches=False,
            reason="metadata_title_missing",
        )

    metadata_canonical = canonicalize_title(metadata_title)
    filename_candidates = canonicalize_filename_stem(path.stem)

    if metadata_canonical in filename_candidates:
        return SampleRow(
            path=path,
            file_name=path.name,
            file_title=file_title,
            metadata_title=metadata_title,
            matches=True,
            reason="exact_or_segment_match",
        )

    if any(metadata_canonical and metadata_canonical in candidate for candidate in filename_candidates):
        return SampleRow(
            path=path,
            file_name=path.name,
            file_title=file_title,
            metadata_title=metadata_title,
            matches=True,
            reason="metadata_contained_in_filename",
        )

    return SampleRow(
        path=path,
        file_name=path.name,
        file_title=file_title,
        metadata_title=metadata_title,
        matches=False,
        reason="title_filename_mismatch",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="抽样统计音频 metadata Title 与文件名的一致率。",
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="要扫描的目录，默认当前目录。",
    )
    parser.add_argument(
        "--sample-size",
        type=int,
        default=50,
        help="抽样数量上限，默认 50。",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=20260407,
        help="抽样随机种子，默认 20260407。",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.98,
        help="判定阈值，默认 0.98。",
    )
    parser.add_argument(
        "--show",
        type=int,
        default=12,
        help="输出样例条数，默认 12。",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = Path(args.path).expanduser().resolve()
    if not root.exists():
        raise SystemExit(f"路径不存在: {root}")

    all_files = collect_audio_files(root)
    if not all_files:
        raise SystemExit("未找到可统计的音频文件。")

    rng = random.Random(args.seed)
    sample_size = min(max(args.sample_size, 1), len(all_files))
    sampled = rng.sample(all_files, sample_size) if sample_size < len(all_files) else all_files
    rows = [compare_title_with_filename(path) for path in sampled]
    matched = [row for row in rows if row.matches]
    mismatched = [row for row in rows if not row.matches]
    consistency = len(matched) / len(rows)

    print(f"扫描根目录: {root}")
    print(f"音频总数: {len(all_files)}")
    print(f"抽样数量: {len(rows)}")
    print(f"一致数量: {len(matched)}")
    print(f"不一致数量: {len(mismatched)}")
    print(f"一致率: {consistency:.2%}")
    print(f"阈值: {args.threshold:.2%}")
    print(f"结论: {'保留 Title 优先可接受' if consistency >= args.threshold else '建议改为只用文件名'}")

    if mismatched:
        print("\n不一致样例:")
        for row in mismatched[: max(args.show, 0)]:
            print(f"- 文件: {row.file_name}")
            print(f"  文件名标题: {row.file_title}")
            print(f"  metadata Title: {row.metadata_title or '<空>'}")
            print(f"  原因: {row.reason}")
            print(f"  路径: {row.path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
