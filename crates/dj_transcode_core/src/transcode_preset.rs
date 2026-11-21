use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioOutputFormat {
    Mp3,
    Wav,
    Aiff,
    Flac,
}

impl AudioOutputFormat {
    pub const fn extension(self) -> &'static str {
        match self {
            Self::Mp3 => "mp3",
            Self::Wav => "wav",
            Self::Aiff => "aiff",
            Self::Flac => "flac",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioChannelMode {
    Original,
    Mono,
    Stereo,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Mp3Preset {
    pub bitrate_kbps: u16,
    pub sample_rate_hz: Option<u32>,
    pub channels: AudioChannelMode,
}

impl Default for Mp3Preset {
    fn default() -> Self {
        Self {
            bitrate_kbps: 320,
            sample_rate_hz: None,
            channels: AudioChannelMode::Original,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WavCodec {
    PcmS16Le,
}

impl WavCodec {
    pub const fn ffmpeg_codec(self) -> &'static str {
        match self {
            Self::PcmS16Le => "pcm_s16le",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct WavPreset {
    pub codec: WavCodec,
    pub sample_rate_hz: Option<u32>,
    pub channels: AudioChannelMode,
}

impl Default for WavPreset {
    fn default() -> Self {
        Self {
            codec: WavCodec::PcmS16Le,
            sample_rate_hz: None,
            channels: AudioChannelMode::Original,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct FlacPreset {
    pub compression_level: u8,
    pub sample_rate_hz: Option<u32>,
    pub channels: AudioChannelMode,
}

impl Default for FlacPreset {
    fn default() -> Self {
        Self {
            compression_level: 5,
            sample_rate_hz: None,
            channels: AudioChannelMode::Original,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "format", content = "config", rename_all = "snake_case")]
pub enum TranscodePreset {
    Mp3(Mp3Preset),
    Wav(WavPreset),
    Aiff(WavPreset),
    Flac(FlacPreset),
}

impl TranscodePreset {
    pub const fn output_format(&self) -> AudioOutputFormat {
        match self {
            Self::Mp3(_) => AudioOutputFormat::Mp3,
            Self::Wav(_) => AudioOutputFormat::Wav,
            Self::Aiff(_) => AudioOutputFormat::Aiff,
            Self::Flac(_) => AudioOutputFormat::Flac,
        }
    }

    pub const fn extension(&self) -> &'static str {
        self.output_format().extension()
    }
}
