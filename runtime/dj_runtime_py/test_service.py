from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import time

from dj_runtime_py.rust_bridge import RustBridgeError, health_check
from dj_runtime_py.search_download_service import SearchDownloadRuntime, TaskState
from dj_runtime_py.service import CleanupDupRuntime


class CleanupDupRuntimeTest(unittest.TestCase):
    def test_rust_bridge_health_check_imports_or_fails_cleanly(self) -> None:
        try:
            result = health_check()
        except RustBridgeError as error:
            self.assertIsInstance(str(error), str)
        else:
            self.assertTrue(result["ok"])
            self.assertIn("health_check", result["capabilities"])

    def test_title_clean_renames_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            target = root / "Track 微信广告.mp3"
            target.write_bytes(b"1234")

            runtime = CleanupDupRuntime()
            load_response = runtime.handle_request(
                {
                    "request_id": "req_001",
                    "module": "cleanup_dup",
                    "action": "load_targets",
                    "payload": {
                        "panel": "title_clean",
                        "file_paths": [str(root)],
                    },
                }
            )
            self.assertTrue(load_response["ok"])

            lock_response = runtime.handle_request(
                {
                    "request_id": "req_002",
                    "module": "cleanup_dup",
                    "action": "lock_config",
                    "payload": {
                        "panel": "title_clean",
                        "config": {"delete_text": "微信广告"},
                    },
                }
            )
            self.assertTrue(lock_response["ok"])

            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_title_clean_task",
                    "payload": {"panel": "title_clean"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            final_status = "running"
            for index in range(10):
                event_response = runtime.handle_request(
                    {
                        "request_id": f"req_004_{index}",
                        "module": "cleanup_dup",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(event_response["ok"])
                events = event_response["data"]["events"]
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)
            renamed = root / "Track.mp3"
            self.assertTrue(renamed.exists())
            self.assertFalse(target.exists())
            self.assertEqual(final_status, "success")

    def test_title_clean_reports_progress_events(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for index in range(3):
                (root / f"Track{index} 微信广告.mp3").write_bytes(b"1234")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {"panel": "title_clean", "file_paths": [str(root)]},
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_002",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {"panel": "title_clean", "config": {"delete_text": "微信广告"}},
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_title_clean_task",
                    "payload": {"panel": "title_clean"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            seen_progress = False
            final_status = "running"
            for index in range(20):
                events_response = runtime.handle_request(
                    {
                        "request_id": f"req_004_{index}",
                        "module": "cleanup_dup",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )

                self.assertTrue(events_response["ok"])
                events = events_response["data"]["events"]
                if any(event["event"] == "task_progress" for event in events):
                    seen_progress = True
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)
            self.assertTrue(seen_progress)
            self.assertEqual(final_status, "success")

    def test_stop_task_cancels_title_clean(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for index in range(40):
                (root / f"Track{index} 微信广告.mp3").write_bytes(b"1234")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {"panel": "title_clean", "file_paths": [str(root)]},
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_002",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {"panel": "title_clean", "config": {"delete_text": "微信广告"}},
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_title_clean_task",
                    "payload": {"panel": "title_clean"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            time.sleep(0.01)
            stop_response = runtime.handle_request(
                {
                    "request_id": "req_004",
                    "module": "cleanup_dup",
                    "action": "stop_task",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(stop_response["ok"])

            final_status = stop_response["data"]["status"]
            for index in range(20):
                events_response = runtime.handle_request(
                    {
                        "request_id": f"req_005_{index}",
                        "module": "cleanup_dup",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(events_response["ok"])
                events = events_response["data"]["events"]
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)
            self.assertEqual(final_status, "cancelled")

    def test_duplicate_review_and_delete_remove_selected_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            keep = root / "Fade.mp3"
            dup = root / "Fade 副本.mp3"
            keep.write_bytes(b"123456")
            dup.write_bytes(b"123")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {
                            "panel": "duplicate_search",
                            "file_paths": [str(root)],
                        },
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_002",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {
                            "panel": "duplicate_search",
                            "config": {
                                "matching_mode": "极速比对",
                                "move_to_recycle_bin": False,
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_duplicate_check_task",
                    "payload": {"panel": "duplicate_search"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            events_response = runtime.handle_request(
                {
                    "request_id": "req_004",
                    "module": "cleanup_dup",
                    "action": "subscribe_task_events",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(events_response["ok"])
            self.assertTrue(
                any(event["event"] == "review_ready" for event in events_response["data"]["events"])
            )

            review_response = runtime.handle_request(
                {
                    "request_id": "req_005",
                    "module": "cleanup_dup",
                    "action": "fetch_review_result",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(review_response["ok"])
            groups = review_response["data"]["groups"]
            self.assertEqual(len(groups), 1)
            selected = [entry for entry in groups[0]["entries"] if entry["is_selected_to_delete"]]
            self.assertEqual(len(selected), 1)

            delete_response = runtime.handle_request(
                {
                    "request_id": "req_006",
                    "module": "cleanup_dup",
                    "action": "execute_delete",
                    "payload": {
                        "task_id": task_id,
                        "move_to_recycle_bin": False,
                        "selected_files": selected,
                    },
                }
            )
            self.assertTrue(delete_response["ok"], delete_response)
            self.assertEqual(delete_response["data"]["deleted_count"], 1)
            self.assertFalse(delete_response["data"]["move_to_recycle_bin"])
            self.assertTrue(keep.exists())
            self.assertFalse(dup.exists())

    def test_duplicate_name_scan_normalizes_copy_variants_and_keeps_largest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            keep = root / "Fade.mp3"
            dup_fullwidth = root / "Ｆａｄｅ（副本）.mp3"
            dup_copy = root / "fade_copy 2.mp3"
            keep.write_bytes(b"123456")
            dup_fullwidth.write_bytes(b"1234")
            dup_copy.write_bytes(b"12")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_101",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {
                            "panel": "duplicate_search",
                            "file_paths": [str(root)],
                        },
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_102",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {
                            "panel": "duplicate_search",
                            "config": {
                                "matching_mode": "极速比对",
                                "move_to_recycle_bin": False,
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_103",
                    "module": "cleanup_dup",
                    "action": "start_duplicate_check_task",
                    "payload": {"panel": "duplicate_search"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            events_response = runtime.handle_request(
                {
                    "request_id": "req_104",
                    "module": "cleanup_dup",
                    "action": "subscribe_task_events",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(events_response["ok"])
            self.assertTrue(
                any(event["event"] == "review_ready" for event in events_response["data"]["events"])
            )

            review_response = runtime.handle_request(
                {
                    "request_id": "req_105",
                    "module": "cleanup_dup",
                    "action": "fetch_review_result",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(review_response["ok"])
            groups = review_response["data"]["groups"]
            self.assertEqual(len(groups), 1)
            self.assertEqual(groups[0]["group_name"], "Fade")
            entries = groups[0]["entries"]
            self.assertEqual(len(entries), 3)

            auto_keep = [entry for entry in entries if entry["is_auto_keep"]]
            self.assertEqual(len(auto_keep), 1)
            self.assertEqual(auto_keep[0]["path"], str(keep.resolve()))

            selected_paths = {entry["path"] for entry in entries if entry["is_selected_to_delete"]}
            self.assertEqual(
                selected_paths,
                {
                    str(dup_fullwidth.resolve()),
                    str(dup_copy.resolve()),
                },
            )

    def test_duplicate_check_content_mode_reports_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = root / "A.mp3"
            second = root / "B.mp3"
            first.write_bytes(b"123456")
            second.write_bytes(b"654321")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {
                            "panel": "duplicate_search",
                            "file_paths": [str(root)],
                        },
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_002",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {
                            "panel": "duplicate_search",
                            "config": {
                                "matching_mode": "内容比对",
                                "move_to_recycle_bin": False,
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_duplicate_check_task",
                    "payload": {"panel": "duplicate_search"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            first_poll = runtime.handle_request(
                {
                    "request_id": "req_004",
                    "module": "cleanup_dup",
                    "action": "subscribe_task_events",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(first_poll["ok"])
            events = first_poll["data"]["events"]
            self.assertTrue(events)
            self.assertTrue(any(event["event"] == "task_progress" for event in events))

            final_status = events[-1]["data"]["status"]
            for index in range(5):
                if final_status != "running":
                    break
                time.sleep(0.05)
                next_poll = runtime.handle_request(
                    {
                        "request_id": f"req_005_{index}",
                        "module": "cleanup_dup",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(next_poll["ok"])
                next_events = next_poll["data"]["events"]
                if next_events:
                    final_status = next_events[-1]["data"]["status"]
            self.assertIn(final_status, {"success", "review_ready", "cancelled"})

    def test_stop_task_marks_content_scan_cancelled(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = root / "A.mp3"
            second = root / "B.mp3"
            first.write_bytes(b"123456")
            second.write_bytes(b"654321")

            runtime = CleanupDupRuntime()
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "cleanup_dup",
                        "action": "load_targets",
                        "payload": {
                            "panel": "duplicate_search",
                            "file_paths": [str(root)],
                        },
                    }
                )["ok"]
            )
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_002",
                        "module": "cleanup_dup",
                        "action": "lock_config",
                        "payload": {
                            "panel": "duplicate_search",
                            "config": {
                                "matching_mode": "内容比对",
                                "move_to_recycle_bin": False,
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "cleanup_dup",
                    "action": "start_duplicate_check_task",
                    "payload": {"panel": "duplicate_search"},
                }
            )
            self.assertTrue(start_response["ok"])
            task_id = start_response["data"]["task_id"]

            stop_response = runtime.handle_request(
                {
                    "request_id": "req_004",
                    "module": "cleanup_dup",
                    "action": "stop_task",
                    "payload": {"task_id": task_id},
                }
            )
            self.assertTrue(stop_response["ok"])
            self.assertEqual(stop_response["data"]["status"], "cancelled")


class _FakeSongInfo:
    def __init__(self, **kwargs):
        self.raw = dict(kwargs)
        for key, value in kwargs.items():
            if key == "save_path":
                continue
            setattr(self, key, value)
        self.source = kwargs.get("source")
        self.root_source = kwargs.get("root_source")
        self.song_name = kwargs.get("song_name")
        self.singers = kwargs.get("singers")
        self.album = kwargs.get("album")
        self.identifier = kwargs.get("identifier")
        self.ext = kwargs.get("ext")
        self.file_size = kwargs.get("file_size")
        self.duration = kwargs.get("duration")
        self.work_dir = kwargs.get("work_dir", "/tmp")
        self.download_url = kwargs.get("download_url")
        self.download_url_status = kwargs.get("download_url_status")
        self.raw_data = kwargs.get("raw_data", self.raw.get("raw_data", {}))
        self._save_path = kwargs.get("save_path") or f"{self.work_dir}/{self.song_name}.{self.ext}"
        provided_valid = kwargs.get("with_valid_download_url", self.raw.get("with_valid_download_url"))
        self.with_valid_download_url = bool(self.download_url) if provided_valid is None else bool(provided_valid)

    @classmethod
    def fromdict(cls, data):
        return cls(**data)

    @property
    def save_path(self):
        return self._save_path

    def todict(self):
        return {
            **self.raw,
            "raw_data": self.raw_data,
            "source": self.source,
            "root_source": self.root_source,
            "song_name": self.song_name,
            "singers": self.singers,
            "album": self.album,
            "identifier": self.identifier,
            "ext": self.ext,
            "file_size": self.file_size,
            "duration": self.duration,
            "work_dir": self.work_dir,
            "download_url": self.download_url,
            "download_url_status": self.download_url_status,
        }


class _FakeDataModule:
    SongInfo = _FakeSongInfo


class _FakeLoggerHandle:
    def info(self, *_args, **_kwargs):
        return None

    def warning(self, *_args, **_kwargs):
        return None

    def error(self, *_args, **_kwargs):
        return None


class _FakeLoggerModule:
    LoggerHandle = _FakeLoggerHandle


class _FakeMusicClientBuilder:
    REGISTERED_MODULES = {
        "QQMusicClient": object(),
        "NeteaseMusicClient": object(),
        "KugouMusicClient": object(),
        "KuwoMusicClient": object(),
        "MiguMusicClient": object(),
        "QianqianMusicClient": object(),
    }


class _FakeSourcesModule:
    MusicClientBuilder = _FakeMusicClientBuilder


class _FakePerSourceClient:
    def __init__(self, source):
        self.source = source
        self.search_size_per_page = 10
        self.strict_limit_search_size_per_page = True
        self.default_cookies = {}

    def _constructsearchurls(self, keyword, rule=None, request_overrides=None):
        if self.source == 'QQMusicClient':
            return [{'url': 'https://fake.qq/search', 'keyword': keyword}]
        return []

    def post(self, url, **_kwargs):
        class _Resp:
            def json(self_nonlocal):
                return {
                    'music.search.SearchCgiService.DoSearchForQQMusicMobile': {
                        'data': {
                            'body': {
                                'item_song': [
                                    {
                                        'mid': '001',
                                        'title': 'fade-A',
                                        'singer': [{'name': 'Singer A'}],
                                        'album': {'title': 'Album A'},
                                        'interval': 192,
                                    },
                                    {
                                        'mid': '002',
                                        'title': 'fade-B',
                                        'singer': [{'name': 'Singer B'}],
                                        'album': {'title': 'Album B'},
                                        'interval': 165,
                                    },
                                ]
                            }
                        }
                    }
                }
        return _Resp()

    def _parsewiththirdpartapis(self, search_result, request_overrides=None):
        identifier = search_result.get('mid') or search_result.get('songmid') or search_result.get('identifier')
        return _FakeSongInfo(
            source=self.source,
            root_source=self.source,
            song_name=search_result.get('title') or search_result.get('song_name') or 'Download Song',
            singers='Singer D',
            album='Album D',
            identifier=str(identifier),
            ext='mp3',
            file_size='7 MB',
            duration='03:00',
            save_path='/tmp/original.mp3',
            with_valid_download_url=True,
            download_url='https://example.test/audio.mp3',
            download_url_status={'ok': True},
        )

    def _parsewithofficialapiv1(self, search_result, song_info_flac=None, lossless_quality_is_sufficient=True, request_overrides=None):
        if song_info_flac is not None and getattr(song_info_flac, "with_valid_download_url", False):
            return song_info_flac
        return self._parsewiththirdpartapis(search_result, request_overrides=request_overrides)


class _FakeMusicClient:
    def __init__(self, music_sources=None, init_music_clients_cfg=None, **_kwargs):
        self.music_sources = music_sources or []
        self.init_music_clients_cfg = init_music_clients_cfg or {}
        self.logger_handle = None
        self.music_clients = {
            source: _FakePerSourceClient(source)
            for source in self.music_sources
        }

    def search(self, keyword):
        return {
            "QQMusicClient": [
                _FakeSongInfo(
                    source="QQMusicClient",
                    root_source="QQMusicClient",
                    song_name=f"{keyword}-A",
                    singers="Singer A",
                    album="Album A",
                    identifier="001",
                    ext="flac",
                    file_size="25 MB",
                    duration="03:12",
                    with_valid_download_url=True,
                    save_path="/tmp/search-a.flac",
                ),
                _FakeSongInfo(
                    source="NeteaseMusicClient",
                    root_source="NeteaseMusicClient",
                    song_name=f"{keyword}-B",
                    singers="Singer B",
                    album="Album B",
                    identifier="002",
                    ext="mp3",
                    file_size="8 MB",
                    duration="02:45",
                    with_valid_download_url=True,
                    save_path="/tmp/search-b.mp3",
                ),
            ]
        }

    def parseplaylist(self, playlist_url):
        return [
            _FakeSongInfo(
                source="QQMusicClient",
                root_source="QQMusicClient",
                song_name="Playlist Song",
                singers="Singer P",
                album="Album P",
                identifier="010",
                ext="mp3",
                file_size="9 MB",
                duration="04:01",
                with_valid_download_url=True,
                save_path="/tmp/playlist.mp3",
                playlist_url=playlist_url,
                playlist_name="午夜热单",
                raw_data={"playlist_name": "午夜热单"},
            )
        ]

    def download(self, song_infos):
        for index, song_info in enumerate(song_infos, start=1):
            if hasattr(song_info, "_save_path"):
                song_info._save_path = f"{getattr(song_info, 'work_dir', '/tmp')}/download-{index}.{getattr(song_info, 'ext', 'mp3')}"
        return None


class _FakeMusicdlModule:
    MusicClient = _FakeMusicClient


class SearchDownloadRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._access_patcher = patch("dj_runtime_py.search_download_service.require_module_access")
        self._access_patcher.start()

    def tearDown(self) -> None:
        self._access_patcher.stop()

    def _fake_modules(self):
        return (
            _FakeMusicdlModule,
            _FakeSourcesModule,
            _FakeDataModule,
            _FakeLoggerModule,
        )

    def test_lock_config_returns_available_sources(self) -> None:
        runtime = SearchDownloadRuntime()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            response = runtime.handle_request(
                {
                    "request_id": "req_sd_001",
                    "module": "search_download",
                    "action": "lock_config",
                    "payload": {
                        "panel": "search",
                        "config": {
                            "output_dir": "/tmp/output",
                            "sources": ["QQ音乐", "网易云"],
                            "keyword": "fade",
                        },
                    },
                }
            )
        self.assertTrue(response["ok"], response)
        self.assertEqual(response["data"]["status"], "config_locked")
        self.assertTrue(any(item["label"] == "QQ音乐" for item in response["data"]["available_sources"]))

    def test_search_task_emits_events_and_fetches_results(self) -> None:
        runtime = SearchDownloadRuntime()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_sd_002",
                        "module": "search_download",
                        "action": "lock_config",
                        "payload": {
                            "panel": "search",
                            "config": {
                                "output_dir": "/tmp/output",
                                "sources": ["QQ音乐", "网易云"],
                                "keyword": "fade",
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_sd_003",
                    "module": "search_download",
                    "action": "start_search_task",
                    "payload": {"panel": "search"},
                }
            )
            self.assertTrue(start_response["ok"], start_response)
            task_id = start_response["data"]["task_id"]

            final_status = "running"
            seen_created = False
            seen_finished = False
            for index in range(20):
                events_response = runtime.handle_request(
                    {
                        "request_id": f"req_sd_004_{index}",
                        "module": "search_download",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(events_response["ok"], events_response)
                events = events_response["data"]["events"]
                seen_created = seen_created or any(event["event"] == "task_created" for event in events)
                seen_finished = seen_finished or any(event["event"] == "task_finished" for event in events)
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)

            self.assertTrue(seen_created)
            self.assertTrue(seen_finished)
            self.assertEqual(final_status, "success")

            result_response = runtime.handle_request(
                {
                    "request_id": "req_sd_005",
                    "module": "search_download",
                    "action": "fetch_search_result",
                    "payload": {"task_id": task_id},
                }
            )
        self.assertTrue(result_response["ok"], result_response)
        self.assertEqual(result_response["data"]["status"], "success")
        self.assertEqual(len(result_response["data"]["results"]), 2)
        self.assertEqual(result_response["data"]["results"][0]["song_name"], "fade-A")

    def test_playlist_parse_task_emits_events_and_fetches_results(self) -> None:
        runtime = SearchDownloadRuntime()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_sd_006",
                        "module": "search_download",
                        "action": "lock_config",
                        "payload": {
                            "panel": "search",
                            "config": {
                                "output_dir": "/tmp/output",
                                "sources": ["QQ音乐"],
                                "playlist_url": "https://music.163.com/#/playlist?id=7583298906",
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_sd_007",
                    "module": "search_download",
                    "action": "start_playlist_parse_task",
                    "payload": {"panel": "search"},
                }
            )
            self.assertTrue(start_response["ok"], start_response)
            task_id = start_response["data"]["task_id"]

            final_status = "running"
            for index in range(20):
                events_response = runtime.handle_request(
                    {
                        "request_id": f"req_sd_008_{index}",
                        "module": "search_download",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(events_response["ok"], events_response)
                events = events_response["data"]["events"]
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)

            result_response = runtime.handle_request(
                {
                    "request_id": "req_sd_013",
                    "module": "search_download",
                    "action": "fetch_search_result",
                    "payload": {"task_id": task_id},
                }
            )
        self.assertEqual(final_status, "success")
        self.assertTrue(result_response["ok"], result_response)
        self.assertEqual(result_response["data"]["task_type"], "playlist_parse")
        self.assertEqual(result_response["data"]["playlist_name"], "午夜热单")
        self.assertEqual(result_response["data"]["output_dir"], os.path.realpath("/tmp/output"))
        self.assertEqual(result_response["data"]["results"][0]["song_name"], "Playlist Song")

    def test_download_task_fetches_download_results(self) -> None:
        runtime = SearchDownloadRuntime()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            self.assertTrue(
                runtime.handle_request(
                    {
                        "request_id": "req_sd_010",
                        "module": "search_download",
                        "action": "lock_config",
                        "payload": {
                            "panel": "search",
                            "config": {
                                "output_dir": "/tmp/output",
                                "sources": ["QQ音乐"],
                            },
                        },
                    }
                )["ok"]
            )
            start_response = runtime.handle_request(
                {
                    "request_id": "req_sd_011",
                    "module": "search_download",
                    "action": "start_download_task",
                    "payload": {
                        "panel": "search",
                        "song_infos": [
                            {
                                "raw_data": {
                                    "search": {
                                        "mid": "900",
                                        "title": "Download Song",
                                        "song_name": "Download Song",
                                    }
                                },
                                "source": "QQMusicClient",
                                "root_source": "QQMusicClient",
                                "song_name": "Download Song",
                                "singers": "Singer D",
                                "album": "Album D",
                                "identifier": "900",
                                "ext": "mp3",
                                "file_size": "7 MB",
                                "duration": "03:00",
                                "save_path": "/tmp/original.mp3",
                                "with_valid_download_url": False,
                            }
                        ],
                    },
                }
            )
            self.assertTrue(start_response["ok"], start_response)
            task_id = start_response["data"]["task_id"]

            final_status = "running"
            for index in range(20):
                events_response = runtime.handle_request(
                    {
                        "request_id": f"req_sd_008_{index}",
                        "module": "search_download",
                        "action": "subscribe_task_events",
                        "payload": {"task_id": task_id},
                    }
                )
                self.assertTrue(events_response["ok"], events_response)
                events = events_response["data"]["events"]
                if events:
                    final_status = events[-1]["data"]["status"]
                if final_status != "running":
                    break
                time.sleep(0.02)

            result_response = runtime.handle_request(
                {
                    "request_id": "req_sd_009",
                    "module": "search_download",
                    "action": "fetch_download_result",
                    "payload": {"task_id": task_id},
                }
            )
        self.assertEqual(final_status, "success")
        self.assertTrue(result_response["ok"], result_response)
        self.assertEqual(result_response["data"]["success_count"], 1)
        self.assertEqual(result_response["data"]["output_dir"], os.path.realpath("/tmp/output"))
        self.assertEqual(
            result_response["data"]["results"][0]["save_path"],
            f"{os.path.realpath('/tmp/output')}/download-1.mp3",
        )

    def test_download_result_response_is_json_safe_when_song_info_contains_bytes(self) -> None:
        runtime = SearchDownloadRuntime()
        resolved_song_info = _FakeSongInfo(
            source="QQMusicClient",
            root_source="QQMusicClient",
            song_name="Binary Song",
            singers="Singer B",
            album="Album B",
            identifier="binary-001",
            ext="flac",
            file_size="102 MB",
            duration="04:30",
            raw_data={
                "search": {
                    "mid": "binary-001",
                    "blob": b"\xff\xfe",
                    "path": Path("/tmp/binary-source"),
                }
            },
            download_url="https://example.test/binary.flac",
            download_url_status={"headers": {"etag": b"binary-etag"}},
            with_valid_download_url=True,
        )

        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            with patch.object(runtime, "_resolve_download_song_infos", return_value=[resolved_song_info]):
                self.assertTrue(
                    runtime.handle_request(
                        {
                            "request_id": "req_sd_bytes_001",
                            "module": "search_download",
                            "action": "lock_config",
                            "payload": {
                                "panel": "search",
                                "config": {
                                    "output_dir": "/tmp/output",
                                    "sources": ["QQ音乐"],
                                },
                            },
                        }
                    )["ok"]
                )
                start_response = runtime.handle_request(
                    {
                        "request_id": "req_sd_bytes_002",
                        "module": "search_download",
                        "action": "start_download_task",
                        "payload": {
                            "panel": "search",
                            "song_infos": [
                                {
                                    "raw_data": {"search": {"mid": "binary-001"}},
                                    "source": "QQMusicClient",
                                    "root_source": "QQMusicClient",
                                    "song_name": "Binary Song",
                                    "identifier": "binary-001",
                                }
                            ],
                        },
                    }
                )
                self.assertTrue(start_response["ok"], start_response)
                task_id = start_response["data"]["task_id"]

                final_status = "running"
                for index in range(20):
                    events_response = runtime.handle_request(
                        {
                            "request_id": f"req_sd_bytes_003_{index}",
                            "module": "search_download",
                            "action": "subscribe_task_events",
                            "payload": {"task_id": task_id},
                        }
                    )
                    self.assertTrue(events_response["ok"], events_response)
                    events = events_response["data"]["events"]
                    if events:
                        final_status = events[-1]["data"]["status"]
                    if final_status != "running":
                        break
                    time.sleep(0.02)

                result_response = runtime.handle_request(
                    {
                        "request_id": "req_sd_bytes_004",
                        "module": "search_download",
                        "action": "fetch_download_result",
                        "payload": {"task_id": task_id},
                    }
                )

        self.assertEqual(final_status, "success")
        self.assertTrue(result_response["ok"], result_response)
        json.dumps(result_response, ensure_ascii=False)
        result = result_response["data"]["results"][0]
        self.assertIsInstance(result["raw_data"]["search"]["blob"], str)
        self.assertEqual(result["raw_data"]["search"]["path"], "/tmp/binary-source")
        self.assertIsInstance(result["download_url_status"]["headers"]["etag"], str)

    def test_start_task_rejects_program_files_output_dir(self) -> None:
        runtime = SearchDownloadRuntime()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            lock_response = runtime.handle_request(
                {
                    "request_id": "req_sd_014",
                    "module": "search_download",
                    "action": "lock_config",
                    "payload": {
                            "panel": "search",
                            "config": {
                                "output_dir": "/Program Files/DJ App/downloads",
                                "sources": ["QQ音乐"],
                                "keyword": "fade",
                        },
                    },
                }
            )
            response = runtime.handle_request(
                {
                    "request_id": "req_sd_015",
                    "module": "search_download",
                    "action": "start_search_task",
                    "payload": {"panel": "search"},
                }
            )
        self.assertTrue(lock_response["ok"])
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_CONFIG")
        self.assertIn("Program Files", response["error"]["message"])

    def test_download_task_prefers_healthy_third_party_methods(self) -> None:
        runtime = SearchDownloadRuntime()
        task = TaskState(
            task_id="task_sd_healthy",
            panel="search",
            task_type="download",
            status="running",
            config={"output_dir": "/tmp/output"},
        )
        task.selected_song_infos = [
            {
                "raw_data": {
                    "search": {
                        "mid": "900",
                        "title": "Download Song",
                        "song_name": "Download Song",
                    }
                },
                "source": "QQMusicClient",
                "root_source": "QQMusicClient",
                "song_name": "Download Song",
                "singers": "Singer D",
                "album": "Album D",
                "identifier": "900",
                "ext": "mp3",
                "file_size": "7 MB",
                "duration": "03:00",
                "with_valid_download_url": False,
            }
        ]
        client = _FakeMusicClient(music_sources=["QQMusicClient"], init_music_clients_cfg={})
        call_sequence: list[str] = []

        def fake_call_parse_with_health(music_client, method_name, raw_search):
            del music_client, raw_search
            call_sequence.append(method_name)
            if method_name == "_parsewithtangapi":
                return (
                    _FakeSongInfo(
                        source="QQMusicClient",
                        root_source="QQMusicClient",
                        song_name="Download Song",
                        singers="Singer D",
                        album="Album D",
                        identifier="900",
                        ext="mp3",
                        file_size="7 MB",
                        duration="03:00",
                        download_url="https://example.test/audio.mp3",
                        download_url_status={"ok": True},
                        with_valid_download_url=True,
                    ),
                    False,
                )
            return (_FakeSongInfo(source="QQMusicClient", with_valid_download_url=False), True)

        def fake_call_parse_if_exists(music_client, method_name, raw_search, request_overrides, **kwargs):
            del music_client, method_name, raw_search, request_overrides
            return kwargs.get("song_info_flac")

        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            with patch.object(runtime, "_call_parse_with_health", side_effect=fake_call_parse_with_health):
                with patch.object(runtime, "_call_parse_if_exists", side_effect=fake_call_parse_if_exists):
                    preferred = runtime._collect_preferred_third_party_methods(task, client)
                    resolved = runtime._resolve_download_song_infos(task, client, preferred)

        self.assertEqual(preferred["QQMusicClient"], ["_parsewithtangapi"])
        self.assertEqual(len(resolved), 1)
        self.assertEqual(resolved[0].download_url, "https://example.test/audio.mp3")
        self.assertEqual(call_sequence.count("_parsewithvkeysapi"), 1)
        self.assertEqual(call_sequence.count("_parsewithtangapi"), 2)
        self.assertTrue(any("已跳过异常下载源" in line for line in task.log_lines))

    def test_parse_call_uses_fast_audio_link_timeout(self) -> None:
        runtime = SearchDownloadRuntime()

        class _Tester:
            def __init__(self):
                self.timeout = (5, 15)
                self.seen_timeout = None

        class _Client:
            source = "QQMusicClient"

            def __init__(self):
                self.audio_link_tester = _Tester()

            def _parsewithvkeysapi(self, search_result=None, request_overrides=None):
                del search_result, request_overrides
                self.audio_link_tester.seen_timeout = self.audio_link_tester.timeout
                return _FakeSongInfo(source=self.source, with_valid_download_url=False)

        client = _Client()
        with patch("dj_runtime_py.search_download_service._ensure_musicdl_loaded", return_value=self._fake_modules()):
            runtime._call_parse_with_health(client, "_parsewithvkeysapi", {"mid": "001"})

        self.assertEqual(client.audio_link_tester.seen_timeout, (2, 4))
        self.assertEqual(client.audio_link_tester.timeout, (5, 15))


if __name__ == "__main__":
    unittest.main()
