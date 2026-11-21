import crypto from "node:crypto"
import fs from "node:fs/promises"
import path from "node:path"
import readline from "node:readline"

const AUDIO_MIME_TYPE = {
  mp3: "audio/mpeg",
  flac: "audio/flac",
  m4a: "audio/mp4",
  ogg: "audio/ogg",
  wma: "audio/x-ms-wma",
  wav: "audio/x-wav",
  dff: "audio/x-dff",
}

const MP3_HEADER = [0x49, 0x44, 0x33]
const FLAC_HEADER = [0x66, 0x4c, 0x61, 0x43]
const OGG_HEADER = [0x4f, 0x67, 0x67, 0x53]
const M4A_HEADER = [0x66, 0x74, 0x79, 0x70]
const WAV_HEADER = [0x52, 0x49, 0x46, 0x46]
const WMA_HEADER = [
  0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11,
  0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62, 0xce, 0x6c,
]
const AAC_HEADER = [0xff, 0xf1]
const DFF_HEADER = [0x46, 0x52, 0x4d, 0x38]
const MAX_INPUT_MB = Math.max(1, Number(process.env.DJ_UNLOCK_MAX_INPUT_MB || 1024))
const MAX_INPUT_BYTES = MAX_INPUT_MB * 1024 * 1024
const TEXT_DECODER = new TextDecoder()

const QMC_HANDLER_MAP = {
  mgg: { ext: "ogg", version: 2 },
  mgg0: { ext: "ogg", version: 2 },
  mggl: { ext: "ogg", version: 2 },
  mgg1: { ext: "ogg", version: 2 },
  mflac: { ext: "flac", version: 2 },
  mflac0: { ext: "flac", version: 2 },
  mmp4: { ext: "m4a", version: 2 },
  qmcflac: { ext: "flac", version: 2 },
  qmcogg: { ext: "ogg", version: 2 },
  qmc0: { ext: "mp3", version: 2 },
  qmc2: { ext: "ogg", version: 2 },
  qmc3: { ext: "mp3", version: 2 },
  bkcmp3: { ext: "mp3", version: 1 },
  bkcflac: { ext: "flac", version: 1 },
  tkm: { ext: "m4a", version: 1 },
  "666c6163": { ext: "flac", version: 1 },
  "6d7033": { ext: "mp3", version: 1 },
  "6f6767": { ext: "ogg", version: 1 },
  "6d3461": { ext: "m4a", version: 1 },
  "776176": { ext: "wav", version: 1 },
}

const VPR_HEADER = [
  0x05, 0x28, 0xbc, 0x96, 0xe9, 0xe4, 0x5a, 0x43,
  0x91, 0xaa, 0xbd, 0xd0, 0x7a, 0xf5, 0x36, 0x31,
]
const KGM_HEADER = [
  0x7c, 0xd5, 0x32, 0xeb, 0x86, 0x02, 0x7f, 0x4b,
  0xa8, 0xaf, 0xa6, 0x8e, 0x0f, 0xff, 0x99, 0x14,
]
const VPR_MASK_DIFF = Buffer.from("25dfe8a6751e750e2f80f32db8b6e31100", "hex")
const KGM_TABLE_1 = Buffer.from("000000000000000000000000000000000001210161012101e101210161012101d223020242420202c2c2020242420202d3d3020363436303e3c3e3036343630394b494650404040484848484040404049595959504052505e585a585e5052505d6b696b6d6270606c6c68686c6c60606d7d79797d7d70607e7c7e787e7c7e70718381878183818e9080808080808080819191919191919190809290969092909da3a1a3a5a3a1a3ada2b0a0a4a4a0a0adbdb1b1b5b5b1b1bdbdb0a0b6b4b6b0b9cbc9c7c1c3c1c7c9cbc9c6d0c0c0c0c9d9d9d9d1d1d1d1d9d9d9d9d0c0d2d0ddebe9ebede3e1e3edebe9ebede2f0e0edfdf9f9fdfdf1f1fdfdf9f9fdfdf0e0f00200060002000e000200060002000f1", "hex")
const KGM_TABLE_2 = Buffer.from("000000000000000000000000000000000001230167012301ef01230167012301df21020246460202cece020246460202dede020365476503edcfed03654765039dbf9d63040404048c8c8c8c040404049c9c9c9c04052705eb8daf8deb052705dbbd9fbddb250606caca8e8ecaca0606dada9e9edada0607e9cbe98fe9cbe907193b197f193b19e70808080808080808181818181818181808092b096f092b09d7391b395f391b39d7290a0a4e4e0a0ad6d61a1a5e5e1a1ad6d60a0b6d4f6d0b95b7957b1d3f1d7b95b7956b0c0c0c0c949494941c1c1c1c949494940c0d2f0dd3b597b5d33d1f3dd3b597b5d32d0e0ed2d29696d2d21e1ed2d29696d2d20e0f00220066002200ee00220066002200fe", "hex")
const KGM_MASK_PRE_DEF = Buffer.from("b8d53db2e9af788c8333715176a0cd372f3e358da9be98b7e78c22ce5a61df686989fea5b6dea977fcc8bdbde56d3e5a36ef694ebee1e9661cf3d902b6f2129b44d06fb93589b6466d73820669c1edd785c230dfa262be792d62623d0d7ebe48892302a0e4d57551320253fd163a213b160fc3b2bbb3e2ba3a3d13ecf6014584a5700f93490c64cd31d5cc4c07019e001a2390bf881e3baba63ec47347107e3b5ebce30084ff09d4e0890f5b58704ffb65d85c531bd3c8c6bfef98b0504f0feae583588c282c8467cdd09e47db2750caf46363e8977f1b4b0cc2c1214ccc58f59452a3f3d3e068f40023f35e0a7b93ddab12b213e884d7a79f0f324c551d043652dc03f3f94e42e93d61ef7cb6b39350", "hex")
const NCM_MAGIC_HEADER = [0x43, 0x54, 0x45, 0x4e, 0x46, 0x44, 0x41, 0x4d]
const NCM_CORE_KEY = Buffer.from("687a4852416d736f356b496e62617857", "hex")
const NCM_META_KEY = Buffer.from("2331346C6A6B5F215C5D2630553C2728", "hex")
const KWM_MAGIC_HEADER = [
  0x79, 0x65, 0x65, 0x6c, 0x69, 0x6f, 0x6e, 0x2d,
  0x6b, 0x75, 0x77, 0x6f, 0x2d, 0x74, 0x6d, 0x65,
]
const KWM_MAGIC_HEADER_2 = [
  0x79, 0x65, 0x65, 0x6c, 0x69, 0x6f, 0x6e, 0x2d,
  0x6b, 0x75, 0x77, 0x6f, 0x00, 0x00, 0x00, 0x00,
]
const KWM_PREDEFINED_KEY = "MoOtOiTvINGwd2E6n0E1i7L5t2IoOoNk"
const XM_MAGIC_HEADER = [0x69, 0x66, 0x6d, 0x74]
const XM_MAGIC_HEADER_2 = [0xfe, 0xfe, 0xfe, 0xfe]
const XM_FILE_TYPE_MAP = {
  " WAV": "wav",
  FLAC: "flac",
  " MP3": "mp3",
  " A4M": "m4a",
}
const TM_HEADER = [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]
const MG3D_SEGMENT_SIZE = 0x20
const QMC_SALT_LEN = 2
const QMC_ZERO_LEN = 7
const QMC_V2_KEY_PREFIX = "QQMusic EncV2,Key:"
const QMC_MIX_KEY_1 = Uint8Array.from([0x33, 0x38, 0x36, 0x5a, 0x4a, 0x59, 0x21, 0x40, 0x23, 0x2a, 0x24, 0x25, 0x5e, 0x26, 0x29, 0x28])
const QMC_MIX_KEY_2 = Uint8Array.from([0x2a, 0x2a, 0x23, 0x21, 0x28, 0x23, 0x24, 0x25, 0x26, 0x5e, 0x61, 0x31, 0x63, 0x5a, 0x2c, 0x54])

function bytesHasPrefix(data, prefix) {
  if (prefix.length > data.length) {
    return false
  }
  return prefix.every((value, index) => value === data[index])
}

function readUint32LE(data, offset = 0) {
  return new DataView(data.buffer, data.byteOffset + offset, 4).getUint32(0, true)
}

function readUint32BE(data, offset = 0) {
  return new DataView(data.buffer, data.byteOffset + offset, 4).getUint32(0, false)
}

function detectAudioExt(data) {
  if (bytesHasPrefix(data, MP3_HEADER)) {
    return "mp3"
  }
  if (bytesHasPrefix(data, FLAC_HEADER)) {
    return "flac"
  }
  if (bytesHasPrefix(data, OGG_HEADER)) {
    return "ogg"
  }
  if (data.length >= 4 + M4A_HEADER.length && bytesHasPrefix(data.slice(4), M4A_HEADER)) {
    return "m4a"
  }
  if (bytesHasPrefix(data, WAV_HEADER)) {
    return "wav"
  }
  if (bytesHasPrefix(data, WMA_HEADER)) {
    return "wma"
  }
  if (bytesHasPrefix(data, AAC_HEADER)) {
    return "aac"
  }
  if (bytesHasPrefix(data, DFF_HEADER)) {
    return "dff"
  }
  return null
}

function sniffAudioExt(data, fallbackExt = "mp3") {
  return detectAudioExt(data) ?? fallbackExt
}

function splitFilename(filename) {
  const index = filename.lastIndexOf(".")
  if (index <= 0) {
    return { name: filename, ext: "" }
  }
  return {
    name: filename.slice(0, index),
    ext: filename.slice(index + 1).toLowerCase(),
  }
}

function ensureSupportedInput(inputPath) {
  if (!path.isAbsolute(inputPath)) {
    throw new Error("input_path must be absolute")
  }
}

function sanitizeOutputName(name) {
  let value = String(name || "")
    .replace(/[\\/:*?"<>|\x00-\x1f]/g, "_")
    .replace(/[. ]+$/g, "")
    .trim()
  if (!value) {
    return "unlocked"
  }
  if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(value)) {
    value = `unlocked_${value}`
  }
  return value.slice(0, 180) || "unlocked"
}


const SAFE_OUTPUT_EXTS = new Set([
  "mp3",
  "flac",
  "m4a",
  "mp4",
  "ogg",
  "wav",
  "wma",
  "aac",
  "dff",
])

function sanitizeOutputExt(ext, fallback = "mp3") {
  const normalized = String(ext || "").trim().toLowerCase().replace(/^\./, "")
  return SAFE_OUTPUT_EXTS.has(normalized) ? normalized : fallback
}

function buildOutputPath(outputDir, name, ext, fallback = "mp3") {
  const resolvedDir = path.resolve(outputDir)
  const safeExt = sanitizeOutputExt(ext, fallback)
  const candidate = path.resolve(
    resolvedDir,
    `${sanitizeOutputName(String(name || ""))}.${safeExt}`,
  )
  if (path.dirname(candidate) !== resolvedDir) {
    throw new Error("output path escapes output directory")
  }
  return candidate
}

async function writeOutputFile(outputPath, inputPath, data) {
  if (path.resolve(outputPath) === path.resolve(inputPath)) {
    throw new Error("output path must not overwrite the source file")
  }
  if (!detectAudioExt(data)) {
    throw new Error("decoded output is not a recognized audio file")
  }
  const tempPath = path.join(
    path.dirname(outputPath),
    `.${path.basename(outputPath)}.${process.pid}.${crypto.randomUUID()}.part`,
  )
  try {
    await fs.writeFile(tempPath, data, { flag: "wx" })
    await fs.rename(tempPath, outputPath)
  } catch (error) {
    await fs.unlink(tempPath).catch(() => undefined)
    throw error
  }
}

async function ensureDirectory(targetDir) {
  await fs.mkdir(targetDir, { recursive: true })
}

async function uniqueOutputPath(targetPath, overwrite) {
  if (overwrite) {
    return targetPath
  }
  try {
    await fs.access(targetPath)
  } catch {
    return targetPath
  }
  const parsed = path.parse(targetPath)
  let index = 1
  while (true) {
    const candidate = path.join(parsed.dir, `${parsed.name} (${index})${parsed.ext}`)
    try {
      await fs.access(candidate)
      index += 1
    } catch {
      return candidate
    }
  }
}

function buildSuccessResult(inputPath, outputPath, ext, title) {
  return {
    input_path: inputPath,
    output_path: outputPath,
    success: true,
    format: ext,
    mime: AUDIO_MIME_TYPE[ext] ?? null,
    title,
  }
}

async function unlockRaw(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const ext = sniffAudioExt(new Uint8Array(fileBuffer), raw.ext || "mp3")
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, fileBuffer)
  return buildSuccessResult(inputPath, outputPath, ext, raw.name)
}

async function unlockNcmCache(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const data = Uint8Array.from(fileBuffer, (byte) => byte ^ 163)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const ext = sniffAudioExt(data, raw.ext || "mp3")
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, Buffer.from(data))
  return buildSuccessResult(inputPath, outputPath, ext, raw.name)
}

function trimKey(raw) {
  if (raw.length > 32) {
    return raw.slice(0, 32)
  }
  if (raw.length < 32) {
    return raw.padEnd(32, raw)
  }
  return raw
}

function createKwmMaskFromKey(keyBytes) {
  const keyValue = keyBytes.readBigUInt64LE(0).toString()
  const trimmed = trimKey(keyValue)
  const mask = Buffer.alloc(32)
  for (let index = 0; index < 32; index += 1) {
    mask[index] = KWM_PREDEFINED_KEY.charCodeAt(index) ^ trimmed.charCodeAt(index)
  }
  return mask
}

async function unlockKwm(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  if (!bytesHasPrefix(fileBuffer, KWM_MAGIC_HEADER) && !bytesHasPrefix(fileBuffer, KWM_MAGIC_HEADER_2)) {
    if (sniffAudioExt(fileBuffer) === "aac") {
      return unlockRaw(inputPath, outputDir, overwrite)
    }
    throw new Error("not a valid kwm file")
  }
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const fileKey = fileBuffer.subarray(0x18, 0x20)
  const mask = createKwmMaskFromKey(fileKey)
  const audioData = Buffer.from(fileBuffer.subarray(0x400))
  for (let index = 0; index < audioData.length; index += 1) {
    audioData[index] ^= mask[index % 0x20]
  }
  const ext = sniffAudioExt(audioData, "mp3")
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, ext, raw.name)
}

async function unlockXm(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  if (!bytesHasPrefix(fileBuffer, XM_MAGIC_HEADER) || !bytesHasPrefix(fileBuffer.subarray(8, 12), XM_MAGIC_HEADER_2)) {
    return unlockRaw(inputPath, outputDir, overwrite)
  }
  const typeText = TEXT_DECODER.decode(fileBuffer.subarray(4, 8))
  const mappedExt = XM_FILE_TYPE_MAP[typeText]
  if (!mappedExt) {
    throw new Error("unknown xm file type")
  }
  const key = fileBuffer[0x0f]
  const dataOffset = fileBuffer[0x0c] | (fileBuffer[0x0d] << 8) | (fileBuffer[0x0e] << 16)
  const audioData = Buffer.from(fileBuffer.subarray(0x10))
  for (let index = dataOffset; index < audioData.length; index += 1) {
    audioData[index] = (audioData[index] - key) ^ 0xff
  }
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, mappedExt),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, mappedExt, raw.name)
}

function isPrintableAsciiChar(value) {
  return value >= 0x20 && value <= 0x7e
}

function isUpperHexChar(value) {
  return (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x46)
}

function decryptMg3dSegment(buffer, key) {
  for (let index = 0; index < buffer.length; index += 1) {
    buffer[index] -= key[index % MG3D_SEGMENT_SIZE]
  }
  return buffer
}

async function unlockMg3d(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const header = fileBuffer.subarray(0, 0x100)
  const bytesRiff = Buffer.from("RIFF", "ascii")
  const bytesWaveFormat = Buffer.from("WAVEfmt ", "ascii")
  let decryptionKey = null
  for (let offset = MG3D_SEGMENT_SIZE; offset < MG3D_SEGMENT_SIZE * 20; offset += MG3D_SEGMENT_SIZE) {
    const possibleKey = fileBuffer.subarray(offset, offset + MG3D_SEGMENT_SIZE)
    if (![...possibleKey].every(isUpperHexChar)) {
      continue
    }
    const tempHeader = decryptMg3dSegment(Buffer.from(header), possibleKey)
    if (!tempHeader.subarray(0, 4).equals(bytesRiff)) {
      continue
    }
    if (!tempHeader.subarray(8, 16).equals(bytesWaveFormat)) {
      continue
    }
    const fmtChunkSize = tempHeader.readUInt32LE(0x10)
    if (![16, 18, 40].includes(fmtChunkSize)) {
      continue
    }
    const firstDataChunkOffset = 0x14 + fmtChunkSize
    const chunkName = tempHeader.subarray(firstDataChunkOffset, firstDataChunkOffset + 4)
    if (![...chunkName].every(isPrintableAsciiChar)) {
      continue
    }
    const secondDataChunkOffset = firstDataChunkOffset + 8 + tempHeader.readUInt32LE(firstDataChunkOffset + 4)
    if (secondDataChunkOffset <= header.length) {
      const secondChunkName = tempHeader.subarray(secondDataChunkOffset, secondDataChunkOffset + 4)
      if (![...secondChunkName].every(isPrintableAsciiChar)) {
        continue
      }
    }
    decryptionKey = Buffer.from(possibleKey)
    break
  }
  if (decryptionKey === null) {
    throw new Error("no suitable mg3d key discovered")
  }
  const audioData = decryptMg3dSegment(Buffer.from(fileBuffer), decryptionKey)
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, "wav"),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, "wav", raw.name)
}

async function unlockTm(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const audioData = Buffer.from(fileBuffer)
  for (let index = 0; index < TM_HEADER.length; index += 1) {
    audioData[index] = TM_HEADER[index]
  }
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, "m4a"),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, "m4a", raw.name)
}

function decryptAesEcb(cipherBytes, key) {
  const decipher = crypto.createDecipheriv("aes-128-ecb", key, null)
  decipher.setAutoPadding(true)
  return Buffer.concat([decipher.update(cipherBytes), decipher.final()])
}

function buildNcmKeyBox(fileBuffer) {
  let offset = 10
  const keyLength = fileBuffer.readUInt32LE(offset)
  offset += 4
  const cipherKey = Buffer.from(fileBuffer.subarray(offset, offset + keyLength))
  offset += keyLength
  for (let index = 0; index < cipherKey.length; index += 1) {
    cipherKey[index] ^= 0x64
  }
  const plainKey = decryptAesEcb(cipherKey, NCM_CORE_KEY)
  const keyData = plainKey.subarray(17)
  const box = Uint8Array.from({ length: 256 }, (_, index) => index)
  let j = 0
  for (let index = 0; index < 256; index += 1) {
    j = (box[index] + j + keyData[index % keyData.length]) & 0xff
    ;[box[index], box[j]] = [box[j], box[index]]
  }
  const keyBox = new Uint8Array(256)
  for (let index = 0; index < 256; index += 1) {
    const step = (index + 1) & 0xff
    const si = box[step]
    const sj = box[(step + si) & 0xff]
    keyBox[index] = box[(si + sj) & 0xff]
  }
  return { keyBox, offset }
}

function parseNcmMeta(fileBuffer, offset) {
  const metaLength = fileBuffer.readUInt32LE(offset)
  offset += 4
  if (metaLength === 0) {
    return { meta: {}, offset }
  }
  const cipherMeta = Buffer.from(fileBuffer.subarray(offset, offset + metaLength))
  offset += metaLength
  for (let index = 0; index < cipherMeta.length; index += 1) {
    cipherMeta[index] ^= 0x63
  }
  const base64Text = cipherMeta.subarray(22).toString("utf8")
  const plainMeta = decryptAesEcb(Buffer.from(base64Text, "base64"), NCM_META_KEY).toString("utf8")
  const labelIndex = plainMeta.indexOf(":")
  if (labelIndex < 0) {
    return { meta: {}, offset }
  }
  const jsonText = plainMeta.slice(labelIndex + 1)
  const parsed = JSON.parse(jsonText)
  const meta = parsed.mainMusic ?? parsed
  return { meta, offset }
}

function decryptNcmAudio(fileBuffer, keyBox, offset) {
  const imageSpace = fileBuffer.readUInt32LE(offset + 5)
  offset += imageSpace + 13
  const audioData = Buffer.from(fileBuffer.subarray(offset))
  for (let index = 0; index < audioData.length; index += 1) {
    audioData[index] ^= keyBox[index & 0xff]
  }
  return audioData
}

async function unlockNcm(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  if (!bytesHasPrefix(new Uint8Array(fileBuffer), NCM_MAGIC_HEADER)) {
    throw new Error("invalid ncm header")
  }
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const keyData = buildNcmKeyBox(fileBuffer)
  const metaData = parseNcmMeta(fileBuffer, keyData.offset)
  const audioData = decryptNcmAudio(fileBuffer, keyData.keyBox, metaData.offset)
  const ext = sanitizeOutputExt(metaData.meta.format, sniffAudioExt(audioData, "mp3"))
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, ext, metaData.meta.musicName || raw.name)
}

class TeaCipher {
  constructor(key, rounds = 64) {
    if (key.length !== 16) {
      throw new Error("incorrect key size")
    }
    if ((rounds & 1) !== 0) {
      throw new Error("odd number of rounds specified")
    }
    this.k0 = readUint32BE(key, 0)
    this.k1 = readUint32BE(key, 4)
    this.k2 = readUint32BE(key, 8)
    this.k3 = readUint32BE(key, 12)
    this.rounds = rounds
  }

  decryptBlock(src) {
    let v0 = readUint32BE(src, 0)
    let v1 = readUint32BE(src, 4)
    let sum = (((0x9e3779b9 * this.rounds) / 2) >>> 0)
    for (let index = 0; index < this.rounds / 2; index += 1) {
      v1 = (v1 - ((((v0 << 4) >>> 0) + this.k2) ^ ((v0 + sum) >>> 0) ^ (((v0 >>> 5) + this.k3) >>> 0))) >>> 0
      v0 = (v0 - ((((v1 << 4) >>> 0) + this.k0) ^ ((v1 + sum) >>> 0) ^ (((v1 >>> 5) + this.k1) >>> 0))) >>> 0
      sum = (sum - 0x9e3779b9) >>> 0
    }
    const output = Buffer.alloc(8)
    output.writeUInt32BE(v0 >>> 0, 0)
    output.writeUInt32BE(v1 >>> 0, 4)
    return output
  }
}

function qmcSimpleMakeKey(salt, length) {
  const keyBuffer = new Uint8Array(length)
  for (let index = 0; index < length; index += 1) {
    const value = Math.tan(salt + index * 0.1)
    keyBuffer[index] = (Math.abs(value) * 100.0) & 0xff
  }
  return keyBuffer
}

function decryptTencentTea(input, key) {
  if (input.length % 8 !== 0) {
    throw new Error("inBuf size not a multiple of the block size")
  }
  if (input.length < 16) {
    throw new Error("inBuf size too small")
  }
  const tea = new TeaCipher(key, 32)
  let tmpBuffer = tea.decryptBlock(input.subarray(0, 8))
  const padLength = tmpBuffer[0] & 0x7
  const outputLength = input.length - 1 - padLength - QMC_SALT_LEN - QMC_ZERO_LEN
  const output = Buffer.alloc(outputLength)
  let ivPrev = Buffer.alloc(8)
  let ivCurrent = Buffer.from(input.subarray(0, 8))
  let inputPosition = 8
  let tmpIndex = 1 + padLength
  const cryptBlock = () => {
    ivPrev = ivCurrent
    ivCurrent = Buffer.from(input.subarray(inputPosition, inputPosition + 8))
    for (let index = 0; index < 8; index += 1) {
      tmpBuffer[index] ^= ivCurrent[index]
    }
    tmpBuffer = tea.decryptBlock(tmpBuffer)
    inputPosition += 8
    tmpIndex = 0
  }
  for (let index = 1; index <= QMC_SALT_LEN;) {
    if (tmpIndex < 8) {
      tmpIndex += 1
      index += 1
    } else {
      cryptBlock()
    }
  }
  let outputPosition = 0
  while (outputPosition < outputLength) {
    if (tmpIndex < 8) {
      output[outputPosition] = tmpBuffer[tmpIndex] ^ ivPrev[tmpIndex]
      outputPosition += 1
      tmpIndex += 1
    } else {
      cryptBlock()
    }
  }
  return output
}

function decryptQmcV2Key(key) {
  if (key.length < QMC_V2_KEY_PREFIX.length || TEXT_DECODER.decode(key.subarray(0, QMC_V2_KEY_PREFIX.length)) !== QMC_V2_KEY_PREFIX) {
    return key
  }
  let output = decryptTencentTea(key.subarray(QMC_V2_KEY_PREFIX.length), QMC_MIX_KEY_1)
  output = decryptTencentTea(output, QMC_MIX_KEY_2)
  const decoded = Buffer.from(TEXT_DECODER.decode(output), "base64")
  if (decoded.length < 16) {
    throw new Error("EncV2 key decode failed")
  }
  return decoded
}

function qmcDeriveKey(raw) {
  let decoded = Buffer.from(TEXT_DECODER.decode(raw), "base64")
  if (decoded.length < 16) {
    throw new Error("key length is too short")
  }
  decoded = decryptQmcV2Key(decoded)
  const simpleKey = qmcSimpleMakeKey(106, 8)
  const teaKey = Buffer.alloc(16)
  for (let index = 0; index < 8; index += 1) {
    teaKey[index * 2] = simpleKey[index]
    teaKey[index * 2 + 1] = decoded[index]
  }
  const decryptedTail = decryptTencentTea(decoded.subarray(8), teaKey)
  decoded.set(decryptedTail, 8)
  return decoded.subarray(0, 8 + decryptedTail.length)
}

class QmcStaticCipher {
  constructor() {
    this.staticCipherBox = Uint8Array.from([
      0x77, 0x48, 0x32, 0x73, 0xde, 0xf2, 0xc0, 0xc8, 0x95, 0xec, 0x30, 0xb2, 0x51, 0xc3, 0xe1, 0xa0,
      0x9e, 0xe6, 0x9d, 0xcf, 0xfa, 0x7f, 0x14, 0xd1, 0xce, 0xb8, 0xdc, 0xc3, 0x4a, 0x67, 0x93, 0xd6,
      0x28, 0xc2, 0x91, 0x70, 0xca, 0x8d, 0xa2, 0xa4, 0xf0, 0x08, 0x61, 0x90, 0x7e, 0x6f, 0xa2, 0xe0,
      0xeb, 0xae, 0x3e, 0xb6, 0x67, 0xc7, 0x92, 0xf4, 0x91, 0xb5, 0xf6, 0x6c, 0x5e, 0x84, 0x40, 0xf7,
      0xf3, 0x1b, 0x02, 0x7f, 0xd5, 0xab, 0x41, 0x89, 0x28, 0xf4, 0x25, 0xcc, 0x52, 0x11, 0xad, 0x43,
      0x68, 0xa6, 0x41, 0x8b, 0x84, 0xb5, 0xff, 0x2c, 0x92, 0x4a, 0x26, 0xd8, 0x47, 0x6a, 0x7c, 0x95,
      0x61, 0xcc, 0xe6, 0xcb, 0xbb, 0x3f, 0x47, 0x58, 0x89, 0x75, 0xc3, 0x75, 0xa1, 0xd9, 0xaf, 0xcc,
      0x08, 0x73, 0x17, 0xdc, 0xaa, 0x9a, 0xa2, 0x16, 0x41, 0xd8, 0xa2, 0x06, 0xc6, 0x8b, 0xfc, 0x66,
      0x34, 0x9f, 0xcf, 0x18, 0x23, 0xa0, 0x0a, 0x74, 0xe7, 0x2b, 0x27, 0x70, 0x92, 0xe9, 0xaf, 0x37,
      0xe6, 0x8c, 0xa7, 0xbc, 0x62, 0x65, 0x9c, 0xc2, 0x08, 0xc9, 0x88, 0xb3, 0xf3, 0x43, 0xac, 0x74,
      0x2c, 0x0f, 0xd4, 0xaf, 0xa1, 0xc3, 0x01, 0x64, 0x95, 0x4e, 0x48, 0x9f, 0xf4, 0x35, 0x78, 0x95,
      0x7a, 0x39, 0xd6, 0x6a, 0xa0, 0x6d, 0x40, 0xe8, 0x4f, 0xa8, 0xef, 0x11, 0x1d, 0xf3, 0x1b, 0x3f,
      0x3f, 0x07, 0xdd, 0x6f, 0x5b, 0x19, 0x30, 0x19, 0xfb, 0xef, 0x0e, 0x37, 0xf0, 0x0e, 0xcd, 0x16,
      0x49, 0xfe, 0x53, 0x47, 0x13, 0x1a, 0xbd, 0xa4, 0xf1, 0x40, 0x19, 0x60, 0x0e, 0xed, 0x68, 0x09,
      0x06, 0x5f, 0x4d, 0xcf, 0x3d, 0x1a, 0xfe, 0x20, 0x77, 0xe4, 0xd9, 0xda, 0xf9, 0xa4, 0x2b, 0x76,
      0x1c, 0x71, 0xdb, 0x00, 0xbc, 0xfd, 0x0c, 0x6c, 0xa5, 0x47, 0xf7, 0xf6, 0x00, 0x79, 0x4a, 0x11,
    ])
  }

  getMask(offset) {
    const current = offset > 0x7fff ? offset % 0x7fff : offset
    return this.staticCipherBox[(current * current + 27) & 0xff]
  }

  decrypt(buffer, offset) {
    for (let index = 0; index < buffer.length; index += 1) {
      buffer[index] ^= this.getMask(offset + index)
    }
  }
}

class QmcMapCipher {
  constructor(key) {
    if (key.length === 0) {
      throw new Error("qmc/cipher_map: invalid key size")
    }
    this.key = key
    this.length = key.length
  }

  static rotate(value, bits) {
    const rotate = (bits + 4) % 8
    return ((value << rotate) | (value >> rotate)) & 0xff
  }

  getMask(offset) {
    const current = offset > 0x7fff ? offset % 0x7fff : offset
    const index = (current * current + 71214) % this.length
    return QmcMapCipher.rotate(this.key[index], index & 0x7)
  }

  decrypt(buffer, offset) {
    for (let index = 0; index < buffer.length; index += 1) {
      buffer[index] ^= this.getMask(offset + index)
    }
  }
}

class QmcRC4Cipher {
  static FIRST_SEGMENT_SIZE = 0x80
  static SEGMENT_SIZE = 5120

  constructor(key) {
    if (key.length === 0) {
      throw new Error("invalid key size")
    }
    this.key = key
    this.length = key.length
    this.seedBox = new Uint8Array(this.length)
    for (let index = 0; index < this.length; index += 1) {
      this.seedBox[index] = index & 0xff
    }
    let swapIndex = 0
    for (let index = 0; index < this.length; index += 1) {
      swapIndex = (this.seedBox[index] + swapIndex + this.key[index % this.length]) % this.length
      ;[this.seedBox[index], this.seedBox[swapIndex]] = [this.seedBox[swapIndex], this.seedBox[index]]
    }
    this.hash = 1
    for (let index = 0; index < this.length; index += 1) {
      const value = this.key[index]
      if (!value) {
        continue
      }
      const nextHash = Math.imul(this.hash, value) >>> 0
      if (nextHash === 0 || nextHash <= this.hash) {
        break
      }
      this.hash = nextHash
    }
  }

  getSegmentKey(id) {
    const seed = this.key[id % this.length]
    const index = Math.floor((this.hash / ((id + 1) * seed)) * 100.0)
    return index % this.length
  }

  decrypt(buffer, offset) {
    let toProcess = buffer.length
    let processed = 0
    const postProcess = (length) => {
      toProcess -= length
      processed += length
      offset += length
      return toProcess === 0
    }
    if (offset < QmcRC4Cipher.FIRST_SEGMENT_SIZE) {
      const segmentLength = Math.min(buffer.length, QmcRC4Cipher.FIRST_SEGMENT_SIZE - offset)
      this.encryptFirstSegment(buffer.subarray(0, segmentLength), offset)
      if (postProcess(segmentLength)) {
        return
      }
    }
    if (offset % QmcRC4Cipher.SEGMENT_SIZE !== 0) {
      const segmentLength = Math.min(QmcRC4Cipher.SEGMENT_SIZE - (offset % QmcRC4Cipher.SEGMENT_SIZE), toProcess)
      this.encryptSegment(buffer.subarray(processed, processed + segmentLength), offset)
      if (postProcess(segmentLength)) {
        return
      }
    }
    while (toProcess > QmcRC4Cipher.SEGMENT_SIZE) {
      this.encryptSegment(buffer.subarray(processed, processed + QmcRC4Cipher.SEGMENT_SIZE), offset)
      postProcess(QmcRC4Cipher.SEGMENT_SIZE)
    }
    if (toProcess > 0) {
      this.encryptSegment(buffer.subarray(processed), offset)
    }
  }

  encryptFirstSegment(buffer, offset) {
    for (let index = 0; index < buffer.length; index += 1) {
      buffer[index] ^= this.key[this.getSegmentKey(offset + index)]
    }
  }

  encryptSegment(buffer, offset) {
    const seedBox = this.seedBox.slice(0)
    const skipLength = (offset % QmcRC4Cipher.SEGMENT_SIZE) + this.getSegmentKey(Math.floor(offset / QmcRC4Cipher.SEGMENT_SIZE))
    let j = 0
    let k = 0
    for (let index = -skipLength; index < buffer.length; index += 1) {
      j = (j + 1) % this.length
      k = (seedBox[j] + k) % this.length
      ;[seedBox[k], seedBox[j]] = [seedBox[j], seedBox[k]]
      if (index >= 0) {
        buffer[index] ^= seedBox[(seedBox[j] + seedBox[k]) % this.length]
      }
    }
  }
}

class QmcDecoder {
  static BYTE_COMMA = ",".charCodeAt(0)

  constructor(file) {
    this.file = file
    this.size = file.length
    this.decoded = false
    this.audioSize = 0
    this.cipher = null
    this.songId = undefined
    this.searchKey()
  }

  decrypt() {
    if (this.cipher === null) {
      throw new Error("no cipher found")
    }
    if (!this.audioSize || this.audioSize <= 0) {
      throw new Error("invalid audio size")
    }
    const audioBuffer = this.file.subarray(0, this.audioSize)
    if (!this.decoded) {
      this.cipher.decrypt(audioBuffer, 0)
      this.decoded = true
    }
    return audioBuffer
  }

  searchKey() {
    const last4Bytes = this.file.subarray(this.size - 4)
    if (TEXT_DECODER.decode(last4Bytes) === "QTag") {
      const keySize = readUint32BE(this.file, this.size - 8)
      this.audioSize = this.size - keySize - 8
      const rawKey = this.file.subarray(this.audioSize, this.size - 8)
      const keyEnd = rawKey.indexOf(QmcDecoder.BYTE_COMMA)
      if (keyEnd < 0) {
        throw new Error("invalid key: search raw key failed")
      }
      this.setCipher(rawKey.subarray(0, keyEnd))
      const idBuffer = rawKey.subarray(keyEnd + 1)
      const idEnd = idBuffer.indexOf(QmcDecoder.BYTE_COMMA)
      const songIdText = TEXT_DECODER.decode(idBuffer.subarray(0, idEnd >= 0 ? idEnd : idBuffer.length))
      const songId = Number.parseInt(songIdText, 10)
      this.songId = Number.isNaN(songId) ? songIdText : songId
      return
    }
    const keySize = readUint32LE(last4Bytes)
    if (keySize < 0x400) {
      this.audioSize = this.size - keySize - 4
      const rawKey = this.file.subarray(this.audioSize, this.size - 4)
      this.setCipher(rawKey)
      return
    }
    this.audioSize = this.size
    this.cipher = new QmcStaticCipher()
  }

  setCipher(rawKey) {
    const decryptedKey = qmcDeriveKey(rawKey)
    if (decryptedKey.length > 300) {
      this.cipher = new QmcRC4Cipher(decryptedKey)
      return
    }
    this.cipher = new QmcMapCipher(decryptedKey)
  }
}

async function unlockQmc(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const handler = QMC_HANDLER_MAP[raw.ext]
  if (!handler) {
    throw new Error(`unsupported qmc type: ${raw.ext}`)
  }
  const decoder = new QmcDecoder(new Uint8Array(fileBuffer))
  const decoded = decoder.decrypt()
  const ext = sniffAudioExt(decoded, handler.ext)
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, Buffer.from(decoded))
  return buildSuccessResult(inputPath, outputPath, ext, raw.name)
}

function getKgmMask(position) {
  let offset = position >> 4
  let value = 0
  while (offset >= 0x11) {
    value ^= KGM_TABLE_1[offset % 272]
    offset >>= 4
    value ^= KGM_TABLE_2[offset % 272]
    offset >>= 4
  }
  return KGM_MASK_PRE_DEF[position % 272] ^ value
}

function decodeKgmByte(byte, key, offset, isVpr) {
  let value = key[offset % 17] ^ byte
  value ^= (value & 0x0f) << 4
  let mask = getKgmMask(offset)
  mask ^= (mask & 0x0f) << 4
  value ^= mask
  if (isVpr) {
    value ^= VPR_MASK_DIFF[offset % 17]
  }
  return value & 0xff
}

async function unlockKgm(inputPath, outputDir, overwrite) {
  const fileBuffer = await fs.readFile(inputPath)
  const bytes = new Uint8Array(fileBuffer)
  const isVpr = bytesHasPrefix(bytes, VPR_HEADER)
  const isKgm = bytesHasPrefix(bytes, KGM_HEADER)
  if (!isVpr && !isKgm) {
    throw new Error("invalid kgm header")
  }
  const headerLength = readUint32LE(bytes, 0x10)
  if (headerLength <= 0x1c || headerLength > bytes.length) {
    throw new Error("invalid kgm header length")
  }
  const keySource = bytes.subarray(0x1c, 0x2c)
  if (keySource.length !== 16) {
    throw new Error("invalid kgm key")
  }
  const key = Buffer.alloc(17)
  keySource.forEach((value, index) => {
    key[index] = value
  })
  const audioData = Buffer.from(bytes.subarray(headerLength))
  for (let index = 0; index < audioData.length; index += 1) {
    audioData[index] = decodeKgmByte(audioData[index], key, index, isVpr)
  }
  const fileName = path.basename(inputPath)
  const raw = splitFilename(fileName)
  const ext = sniffAudioExt(audioData, "mp3")
  await ensureDirectory(outputDir)
  const outputPath = await uniqueOutputPath(
    buildOutputPath(outputDir, raw.name, ext),
    overwrite,
  )
  await writeOutputFile(outputPath, inputPath, audioData)
  return buildSuccessResult(inputPath, outputPath, ext, raw.name)
}

async function unlockFile(payload) {
  const inputPath = String(payload.input_path || "")
  const outputDir = String(payload.output_dir || "")
  const overwrite = Boolean(payload.overwrite)
  ensureSupportedInput(inputPath)
  ensureSupportedInput(outputDir)
  const inputStat = await fs.stat(inputPath)
  if (!inputStat.isFile()) {
    throw new Error("input path is not a file")
  }
  if (inputStat.size > MAX_INPUT_BYTES) {
    throw new Error("input file is too large (limit: " + MAX_INPUT_MB + " MB)")
  }
  const ext = splitFilename(path.basename(inputPath)).ext
  if (["mp3", "flac", "m4a", "ogg", "wav", "wma", "aac", "dff", "ofl_en"].includes(ext)) {
    return { result: await unlockRaw(inputPath, outputDir, overwrite) }
  }
  if (ext === "uc" || ext === "cache") {
    return { result: await unlockNcmCache(inputPath, outputDir, overwrite) }
  }
  if (ext === "ncm") {
    return { result: await unlockNcm(inputPath, outputDir, overwrite) }
  }
  if (ext === "kwm") {
    return { result: await unlockKwm(inputPath, outputDir, overwrite) }
  }
  if (ext === "xm") {
    return { result: await unlockXm(inputPath, outputDir, overwrite) }
  }
  if (ext === "mg3d") {
    return { result: await unlockMg3d(inputPath, outputDir, overwrite) }
  }
  if (["tm0", "tm2", "tm3", "tm6"].includes(ext)) {
    return { result: await unlockTm(inputPath, outputDir, overwrite) }
  }
  if (["qmc0", "qmc2", "qmc3", "bkcmp3", "bkcflac", "tkm", "666c6163", "6d7033", "6f6767", "6d3461", "776176", "mgg", "mgg0", "mggl", "mgg1", "mflac", "mflac0", "mmp4", "qmcflac", "qmcogg"].includes(ext)) {
    return { result: await unlockQmc(inputPath, outputDir, overwrite) }
  }
  if (["kgm", "kgma", "vpr"].includes(ext)) {
    return { result: await unlockKgm(inputPath, outputDir, overwrite) }
  }
  throw new Error(`unsupported format: ${ext || "unknown"}`)
}

async function unlockBatch(payload) {
  const inputPaths = Array.isArray(payload.input_paths)
    ? payload.input_paths.map((item) => String(item))
    : []
  const outputDir = String(payload.output_dir || "")
  const overwrite = Boolean(payload.overwrite)
  ensureSupportedInput(outputDir)
  const results = []
  for (const inputPath of inputPaths) {
    try {
      const { result } = await unlockFile({ input_path: inputPath, output_dir: outputDir, overwrite })
      results.push(result)
    } catch (error) {
      results.push({
        input_path: inputPath,
        output_path: null,
        success: false,
        error: error instanceof Error ? error.message : String(error),
      })
    }
  }
  const successCount = results.filter((item) => item.success).length
  return {
    results,
    success_count: successCount,
    failure_count: results.length - successCount,
  }
}

async function dispatch(action, payload) {
  switch (action) {
    case "health_check":
      return {
        runtime: "node",
        core: "unlock_music",
        capabilities: ["health_check", "unlock_file", "unlock_batch"],
      }
    case "unlock_file":
      return await unlockFile(payload)
    case "unlock_batch":
      return await unlockBatch(payload)
    default:
      throw new Error(`unknown action: ${action}`)
  }
}

function writeResponse(response) {
  process.stdout.write(`${JSON.stringify(response)}\n`)
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
})

rl.on("line", async (line) => {
  if (!line.trim()) {
    return
  }
  let request
  try {
    request = JSON.parse(line)
    const data = await dispatch(request.action, request.payload ?? {})
    writeResponse({ id: request.id ?? null, ok: true, data })
  } catch (error) {
    writeResponse({
      id: request?.id ?? null,
      ok: false,
      error: {
        code: "UNLOCK_FAILED",
        message: error instanceof Error ? error.message : String(error),
      },
    })
  }
})
