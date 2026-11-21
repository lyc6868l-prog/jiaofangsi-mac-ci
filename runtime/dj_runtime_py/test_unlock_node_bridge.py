from __future__ import annotations

import base64
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from dj_runtime_py.__main__ import _resolve_unlock_worker_root
from dj_runtime_py.unlock_node_bridge import UnlockNodeBridge


class UnlockNodeBridgeTest(unittest.TestCase):
    _ncm_core_key = bytes.fromhex("687a4852416d736f356b496e62617857")
    _ncm_meta_key = bytes.fromhex("2331346C6A6B5F215C5D2630553C2728")

    def test_resolve_unlock_worker_root_points_to_existing_worker(self) -> None:
        worker_root = _resolve_unlock_worker_root()
        self.assertTrue((worker_root / "src" / "main.js").exists())

    def _create_bridge(self) -> UnlockNodeBridge:
        repo_root = Path(__file__).resolve().parents[2]
        worker_root = repo_root / "runtime" / "unlock_music_node"
        return UnlockNodeBridge(
            node_executable="node",
            working_directory=str(worker_root),
            entry_script=str(worker_root / "src" / "main.js"),
        )

    def _aes_ecb_encrypt(self, data: bytes, key: bytes) -> bytes:
        script = (
            "const crypto = require('node:crypto');"
            "const key = Buffer.from(process.argv[1], 'hex');"
            "const data = Buffer.from(process.argv[2], 'hex');"
            "const padding = 16 - (data.length % 16);"
            "const padded = Buffer.concat([data, Buffer.alloc(padding, padding)]);"
            "const cipher = crypto.createCipheriv('aes-128-ecb', key, null);"
            "cipher.setAutoPadding(false);"
            "process.stdout.write(Buffer.concat([cipher.update(padded), cipher.final()]).toString('hex'));"
        )
        encrypted_hex = subprocess.check_output(
            ["node", "-e", script, key.hex(), data.hex()],
            text=True,
        ).strip()
        return bytes.fromhex(encrypted_hex)

    def _build_ncm_fixture(self, output_audio: bytes, output_format: str) -> bytes:
        key_plain = b"neteasecloudmusic" + bytes(range(1, 17))
        key_cipher = bytearray(self._aes_ecb_encrypt(key_plain, self._ncm_core_key))
        for index in range(len(key_cipher)):
            key_cipher[index] ^= 0x64

        meta_json = json.dumps(
            {
                "musicName": "Fixture Song",
                "artist": [["Fixture Artist", 1]],
                "format": output_format,
                "album": "Fixture Album",
            },
            separators=(",", ":"),
        ).encode("utf-8")
        meta_plain = b"music:" + meta_json
        meta_cipher = bytearray(
            b"163 key(Don't modify):" + base64.b64encode(self._aes_ecb_encrypt(meta_plain, self._ncm_meta_key))
        )
        for index in range(len(meta_cipher)):
            meta_cipher[index] ^= 0x63

        key_stream = key_plain[17:]
        box = list(range(256))
        j = 0
        for index in range(256):
            j = (box[index] + j + key_stream[index % len(key_stream)]) & 0xFF
            box[index], box[j] = box[j], box[index]
        key_box = []
        for index in range(256):
            step = (index + 1) & 0xFF
            si = box[step]
            sj = box[(step + si) & 0xFF]
            key_box.append(box[(si + sj) & 0xFF])

        encrypted_audio = bytearray(output_audio)
        for index in range(len(encrypted_audio)):
            encrypted_audio[index] ^= key_box[index & 0xFF]

        return b"CTENFDAM" + b"\x00\x00" + (
            len(key_cipher).to_bytes(4, "little")
            + bytes(key_cipher)
            + len(meta_cipher).to_bytes(4, "little")
            + bytes(meta_cipher)
            + b"\x00" * 9
            + (0).to_bytes(4, "little")
            + bytes(encrypted_audio)
        )

    def _qmc_static_mask(self, offset: int) -> int:
        static_cipher_box = (
            0x77, 0x48, 0x32, 0x73, 0xDE, 0xF2, 0xC0, 0xC8, 0x95, 0xEC, 0x30, 0xB2, 0x51, 0xC3, 0xE1, 0xA0,
            0x9E, 0xE6, 0x9D, 0xCF, 0xFA, 0x7F, 0x14, 0xD1, 0xCE, 0xB8, 0xDC, 0xC3, 0x4A, 0x67, 0x93, 0xD6,
            0x28, 0xC2, 0x91, 0x70, 0xCA, 0x8D, 0xA2, 0xA4, 0xF0, 0x08, 0x61, 0x90, 0x7E, 0x6F, 0xA2, 0xE0,
            0xEB, 0xAE, 0x3E, 0xB6, 0x67, 0xC7, 0x92, 0xF4, 0x91, 0xB5, 0xF6, 0x6C, 0x5E, 0x84, 0x40, 0xF7,
            0xF3, 0x1B, 0x02, 0x7F, 0xD5, 0xAB, 0x41, 0x89, 0x28, 0xF4, 0x25, 0xCC, 0x52, 0x11, 0xAD, 0x43,
            0x68, 0xA6, 0x41, 0x8B, 0x84, 0xB5, 0xFF, 0x2C, 0x92, 0x4A, 0x26, 0xD8, 0x47, 0x6A, 0x7C, 0x95,
            0x61, 0xCC, 0xE6, 0xCB, 0xBB, 0x3F, 0x47, 0x58, 0x89, 0x75, 0xC3, 0x75, 0xA1, 0xD9, 0xAF, 0xCC,
            0x08, 0x73, 0x17, 0xDC, 0xAA, 0x9A, 0xA2, 0x16, 0x41, 0xD8, 0xA2, 0x06, 0xC6, 0x8B, 0xFC, 0x66,
            0x34, 0x9F, 0xCF, 0x18, 0x23, 0xA0, 0x0A, 0x74, 0xE7, 0x2B, 0x27, 0x70, 0x92, 0xE9, 0xAF, 0x37,
            0xE6, 0x8C, 0xA7, 0xBC, 0x62, 0x65, 0x9C, 0xC2, 0x08, 0xC9, 0x88, 0xB3, 0xF3, 0x43, 0xAC, 0x74,
            0x2C, 0x0F, 0xD4, 0xAF, 0xA1, 0xC3, 0x01, 0x64, 0x95, 0x4E, 0x48, 0x9F, 0xF4, 0x35, 0x78, 0x95,
            0x7A, 0x39, 0xD6, 0x6A, 0xA0, 0x6D, 0x40, 0xE8, 0x4F, 0xA8, 0xEF, 0x11, 0x1D, 0xF3, 0x1B, 0x3F,
            0x3F, 0x07, 0xDD, 0x6F, 0x5B, 0x19, 0x30, 0x19, 0xFB, 0xEF, 0x0E, 0x37, 0xF0, 0x0E, 0xCD, 0x16,
            0x49, 0xFE, 0x53, 0x47, 0x13, 0x1A, 0xBD, 0xA4, 0xF1, 0x40, 0x19, 0x60, 0x0E, 0xED, 0x68, 0x09,
            0x06, 0x5F, 0x4D, 0xCF, 0x3D, 0x1A, 0xFE, 0x20, 0x77, 0xE4, 0xD9, 0xDA, 0xF9, 0xA4, 0x2B, 0x76,
            0x1C, 0x71, 0xDB, 0x00, 0xBC, 0xFD, 0x0C, 0x6C, 0xA5, 0x47, 0xF7, 0xF6, 0x00, 0x79, 0x4A, 0x11,
        )
        current = offset % 0x7FFF if offset > 0x7FFF else offset
        return static_cipher_box[(current * current + 27) & 0xFF]

    def _build_qmc_static_fixture(self) -> bytes:
        plain = bytearray(b"ID3demo-qmc-static")
        desired_tail = b"\x00\x04\x00\x00"
        start = len(plain) - 4
        for index, value in enumerate(desired_tail):
            plain[start + index] = value ^ self._qmc_static_mask(start + index)
        encrypted = bytearray(plain)
        for index in range(len(encrypted)):
            encrypted[index] ^= self._qmc_static_mask(index)
        self.assertGreaterEqual(int.from_bytes(encrypted[-4:], "little"), 0x400)
        return bytes(encrypted)

    def _tea_encrypt_block(self, block: bytes, key: bytes) -> bytes:
        k0 = int.from_bytes(key[0:4], "big")
        k1 = int.from_bytes(key[4:8], "big")
        k2 = int.from_bytes(key[8:12], "big")
        k3 = int.from_bytes(key[12:16], "big")
        v0 = int.from_bytes(block[0:4], "big")
        v1 = int.from_bytes(block[4:8], "big")
        tea_delta = 0x9E3779B9
        value_mask = 0xFFFFFFFF
        tea_sum = 0
        for _ in range(16):
            tea_sum = (tea_sum + tea_delta) & value_mask
            v0 = (v0 + (((v1 << 4) + k0) ^ (v1 + tea_sum) ^ ((v1 >> 5) + k1))) & value_mask
            v1 = (v1 + (((v0 << 4) + k2) ^ (v0 + tea_sum) ^ ((v0 >> 5) + k3))) & value_mask
        return v0.to_bytes(4, "big") + v1.to_bytes(4, "big")

    def _encrypt_tencent_tea(self, body: bytes, key: bytes) -> bytes:
        pad_salt_body_zero_len = len(body) + 1 + 2 + 7
        pad_len = (8 - (pad_salt_body_zero_len % 8)) % 8
        src_buf = bytearray(8)
        src_buf[0] = pad_len
        tmp_idx = 1 + pad_len
        iv_plain = bytearray(8)
        iv_crypt = bytearray(8)
        output = bytearray()

        def crypt_block() -> None:
            nonlocal tmp_idx, iv_plain, iv_crypt
            block = bytearray(src_buf)
            for index in range(8):
                block[index] ^= iv_crypt[index]
            cipher = bytearray(self._tea_encrypt_block(bytes(block), key))
            for index in range(8):
                cipher[index] ^= iv_plain[index]
            iv_plain = bytearray(src_buf)
            iv_crypt = cipher
            output.extend(cipher)
            tmp_idx = 0

        for _ in range(2):
            if tmp_idx == 8:
                crypt_block()
            src_buf[tmp_idx] = 0
            tmp_idx += 1
        for value in body:
            if tmp_idx == 8:
                crypt_block()
            src_buf[tmp_idx] = value
            tmp_idx += 1
        for _ in range(7):
            if tmp_idx == 8:
                crypt_block()
            src_buf[tmp_idx] = 0
            tmp_idx += 1
        if tmp_idx == 8:
            crypt_block()
        return bytes(output)

    def _qmc_simple_make_key(self, salt: int, length: int) -> bytes:
        return bytes(int(abs(__import__("math").tan(salt + index * 0.1)) * 100.0) & 0xFF for index in range(length))

    def _qmc_map_mask(self, key: bytes, offset: int) -> int:
        current = offset % 0x7FFF if offset > 0x7FFF else offset
        index = (current * current + 71214) % len(key)
        rotate = (index & 0x7) + 4
        rotate %= 8
        value = key[index]
        return ((value << rotate) | (value >> rotate)) & 0xFF

    def _build_qmc_v2_fixture(self, output_audio: bytes) -> bytes:
        key_decoded = b"12345678abcdefgh"
        simple_key = self._qmc_simple_make_key(106, 8)
        tea_key = bytearray(16)
        for index in range(8):
            tea_key[index * 2] = simple_key[index]
            tea_key[index * 2 + 1] = key_decoded[index]
        raw_key = key_decoded[:8] + self._encrypt_tencent_tea(key_decoded[8:], bytes(tea_key))
        encoded_audio = bytearray(output_audio)
        for index in range(len(encoded_audio)):
            encoded_audio[index] ^= self._qmc_map_mask(key_decoded, index)
        key_blob = base64.b64encode(raw_key)
        return bytes(encoded_audio) + key_blob + len(key_blob).to_bytes(4, "little")

    def _kgm_mask(self, offset: int) -> int:
        table1 = bytes.fromhex(
            "000000000000000000000000000000000001210161012101e101210161012101d223020242420202c2c2020242420202d3d3020363436303e3c3e3036343630394b494650404040484848484040404049595959504052505e585a585e5052505d6b696b6d6270606c6c68686c6c60606d7d79797d7d70607e7c7e787e7c7e70718381878183818e9080808080808080819191919191919190809290969092909da3a1a3a5a3a1a3ada2b0a0a4a4a0a0adbdb1b1b5b5b1b1bdbdb0a0b6b4b6b0b9cbc9c7c1c3c1c7c9cbc9c6d0c0c0c0c9d9d9d9d1d1d1d1d9d9d9d9d0c0d2d0ddebe9ebede3e1e3edebe9ebede2f0e0edfdf9f9fdfdf1f1fdfdf9f9fdfdf0e0f00200060002000e000200060002000f1"
        )
        table2 = bytes.fromhex(
            "000000000000000000000000000000000001230167012301ef01230167012301df21020246460202cece020246460202dede020365476503edcfed03654765039dbf9d63040404048c8c8c8c040404049c9c9c9c04052705eb8daf8deb052705dbbd9fbddb250606caca8e8ecaca0606dada9e9edada0607e9cbe98fe9cbe907193b197f193b19e70808080808080808181818181818181808092b096f092b09d7391b395f391b39d7290a0a4e4e0a0ad6d61a1a5e5e1a1ad6d60a0b6d4f6d0b95b7957b1d3f1d7b95b7956b0c0c0c0c949494941c1c1c1c949494940c0d2f0dd3b597b5d33d1f3dd3b597b5d32d0e0ed2d29696d2d21e1ed2d29696d2d20e0f00220066002200ee00220066002200fe"
        )
        mask_pre_def = bytes.fromhex(
            "b8d53db2e9af788c8333715176a0cd372f3e358da9be98b7e78c22ce5a61df686989fea5b6dea977fcc8bdbde56d3e5a36ef694ebee1e9661cf3d902b6f2129b44d06fb93589b6466d73820669c1edd785c230dfa262be792d62623d0d7ebe48892302a0e4d57551320253fd163a213b160fc3b2bbb3e2ba3a3d13ecf6014584a5700f93490c64cd31d5cc4c07019e001a2390bf881e3baba63ec47347107e3b5ebce30084ff09d4e0890f5b58704ffb65d85c531bd3c8c6bfef98b0504f0feae583588c282c8467cdd09e47db2750caf46363e8977f1b4b0cc2c1214ccc58f59452a3f3d3e068f40023f35e0a7b93ddab12b213e884d7a79f0f324c551d043652dc03f3f94e42e93d61ef7cb6b39350"
        )
        value = 0
        current = offset >> 4
        while current >= 0x11:
            value ^= table1[current % 272]
            current >>= 4
            value ^= table2[current % 272]
            current >>= 4
        return mask_pre_def[offset % 272] ^ value

    def _build_kgm_fixture(self, output_audio: bytes, *, is_vpr: bool) -> bytes:
        vpr_mask_diff = bytes.fromhex("25dfe8a6751e750e2f80f32db8b6e31100")
        key = bytes(range(1, 17)) + b"\x00"
        encoded_audio = bytearray(output_audio)
        for index, value in enumerate(output_audio):
            plain = value ^ (vpr_mask_diff[index % 17] if is_vpr else 0)
            mask = self._kgm_mask(index)
            mask ^= (mask & 0x0F) << 4
            transformed = plain ^ mask
            transformed ^= (transformed & 0x0F) << 4
            encoded_audio[index] = key[index % 17] ^ transformed
        header_len = 0x2C
        header = bytearray(header_len)
        magic = bytes.fromhex("0528bc96e9e45a4391aabdd07af53631" if is_vpr else "7cd532eb86027f4ba8afa68e0fff9914")
        header[:16] = magic
        header[0x10:0x14] = header_len.to_bytes(4, "little")
        header[0x1C:0x2C] = key[:16]
        return bytes(header) + bytes(encoded_audio)

    def _assert_unlock_success(
        self,
        bridge: UnlockNodeBridge,
        input_path: Path,
        output_dir: Path,
        expected_format: str,
    ) -> None:
        result = bridge.unlock_file(
            input_path=str(input_path),
            output_dir=str(output_dir),
            overwrite=False,
            keep_source=True,
        )
        payload = result["result"]
        self.assertTrue(payload["success"])
        self.assertEqual(payload["format"], expected_format)
        self.assertTrue(Path(payload["output_path"]).exists())

    def test_health_check_returns_capabilities(self) -> None:
        bridge = self._create_bridge()
        try:
            result = bridge.health_check()
        finally:
            bridge.close()
        self.assertEqual(result["runtime"], "node")
        self.assertIn("unlock_file", result["capabilities"])

    def test_unlock_raw_mp3_copies_to_output_dir(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "Demo.mp3"
            output_dir = root / "out"
            source.write_bytes(b"ID3" + b"demo-audio")
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()

    def test_unlock_uc_cache_decodes_to_mp3(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "Demo.uc"
            output_dir = root / "out"
            encoded = bytes(byte ^ 163 for byte in (b"ID3" + b"demo-audio"))
            source.write_bytes(encoded)
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()

    def test_unlock_tm_writes_m4a_header(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "Demo.tm2"
            output_dir = root / "out"
            source.write_bytes(b"12345678rest-of-demo")
            try:
                self._assert_unlock_success(bridge, source, output_dir, "m4a")
            finally:
                bridge.close()

    def test_unlock_qmc_static_decodes_to_mp3(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            source = root / "Fixture.bkcmp3"
            source.write_bytes(self._build_qmc_static_fixture())
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()

    def test_unlock_qmc_v2_js_decodes_to_mp3(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            source = root / "Fixture.qmc0"
            source.write_bytes(self._build_qmc_v2_fixture(b"ID3demo-qmc-v2"))
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()

    def test_unlock_kgm_decodes_to_mp3(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            source = root / "Fixture.kgm"
            source.write_bytes(self._build_kgm_fixture(b"ID3demo-kgm", is_vpr=False))
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()

    def test_unlock_vpr_decodes_to_flac(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            source = root / "Fixture.vpr"
            source.write_bytes(self._build_kgm_fixture(b"fLaCdemo-vpr", is_vpr=True))
            try:
                self._assert_unlock_success(bridge, source, output_dir, "flac")
            finally:
                bridge.close()

    def test_unlock_batch_collects_mixed_results(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            valid = root / "Good.mp3"
            invalid = root / "Bad.ncm"
            valid.write_bytes(b"ID3" + b"demo-audio")
            invalid.write_bytes(b"broken")
            try:
                result = bridge.request(
                    "unlock_batch",
                    {
                        "input_paths": [str(valid), str(invalid)],
                        "output_dir": str(output_dir),
                        "overwrite": False,
                        "keep_source": True,
                    },
                )
            finally:
                bridge.close()
        self.assertEqual(result["success_count"], 1)
        self.assertEqual(result["failure_count"], 1)
        self.assertEqual(len(result["results"]), 2)

    def test_unlock_ncm_decodes_to_mp3(self) -> None:
        bridge = self._create_bridge()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "out"
            source = root / "Fixture.ncm"
            source.write_bytes(self._build_ncm_fixture(b"ID3" + b"ncm-demo-audio", "mp3"))
            try:
                self._assert_unlock_success(bridge, source, output_dir, "mp3")
            finally:
                bridge.close()


if __name__ == "__main__":
    unittest.main()
