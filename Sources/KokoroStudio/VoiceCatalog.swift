import Foundation

struct Voice: Identifiable, Hashable {
    let id: Int
    let name: String
    let tagline: String?
    let recommended: Bool

    init(id: Int, name: String, tagline: String? = nil, recommended: Bool = false) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.recommended = recommended
    }

    /// Picker row label, e.g. "★ af_heart — warm, expressive".
    var displayName: String {
        var label = recommended ? "★ \(name)" : name
        if let tagline { label += " — \(tagline)" }
        return label
    }
}

/// Speaker IDs for kokoro-multi-lang-v1_0 (53 speakers, verified against the
/// sherpa-onnx documentation table). Taglines are informal listening notes;
/// ★ marks the strongest all-purpose voices.
enum VoiceCatalog {
    static let all: [Voice] = [
        // American female (0–10)
        Voice(id: 0, name: "af_alloy", tagline: "neutral, even"),
        Voice(id: 1, name: "af_aoede", tagline: "smooth, low-key"),
        Voice(id: 2, name: "af_bella", tagline: "bright, energetic", recommended: true),
        Voice(id: 3, name: "af_heart", tagline: "warm, expressive", recommended: true),
        Voice(id: 4, name: "af_jessica", tagline: "crisp, direct"),
        Voice(id: 5, name: "af_kore", tagline: "clear, composed"),
        Voice(id: 6, name: "af_nicole", tagline: "soft, breathy"),
        Voice(id: 7, name: "af_nova", tagline: "polished, announcer-ish"),
        Voice(id: 8, name: "af_river", tagline: "relaxed, airy"),
        Voice(id: 9, name: "af_sarah", tagline: "calm, steady"),
        Voice(id: 10, name: "af_sky", tagline: "light, youthful"),
        // American male (11–19)
        Voice(id: 11, name: "am_adam", tagline: "deep, authoritative"),
        Voice(id: 12, name: "am_echo", tagline: "mellow, mid-pitch"),
        Voice(id: 13, name: "am_eric", tagline: "plain, conversational"),
        Voice(id: 14, name: "am_fenrir", tagline: "strong, resonant"),
        Voice(id: 15, name: "am_liam", tagline: "young, casual"),
        Voice(id: 16, name: "am_michael", tagline: "friendly, natural"),
        Voice(id: 17, name: "am_onyx", tagline: "very deep, gravelly"),
        Voice(id: 18, name: "am_puck", tagline: "playful, upbeat"),
        Voice(id: 19, name: "am_santa", tagline: "jolly, theatrical"),
        // British female (20–23)
        Voice(id: 20, name: "bf_alice", tagline: "refined, gentle"),
        Voice(id: 21, name: "bf_emma", tagline: "natural, mellow"),
        Voice(id: 22, name: "bf_isabella", tagline: "clear, formal"),
        Voice(id: 23, name: "bf_lily", tagline: "soft, light"),
        // British male (24–27)
        Voice(id: 24, name: "bm_daniel", tagline: "understated, even"),
        Voice(id: 25, name: "bm_fable", tagline: "storyteller, lively"),
        Voice(id: 26, name: "bm_george", tagline: "classic British, clear", recommended: true),
        Voice(id: 27, name: "bm_lewis", tagline: "low, measured"),
        // Other languages (28–52)
        Voice(id: 28, name: "ef_dora"), Voice(id: 29, name: "em_alex"),
        Voice(id: 30, name: "ff_siwis"),
        Voice(id: 31, name: "hf_alpha"), Voice(id: 32, name: "hf_beta"),
        Voice(id: 33, name: "hm_omega"), Voice(id: 34, name: "hm_psi"),
        Voice(id: 35, name: "if_sara"), Voice(id: 36, name: "im_nicola"),
        Voice(id: 37, name: "jf_alpha"), Voice(id: 38, name: "jf_gongitsune"),
        Voice(id: 39, name: "jf_nezumi"), Voice(id: 40, name: "jf_tebukuro"),
        Voice(id: 41, name: "jm_kumo"),
        Voice(id: 42, name: "pf_dora"), Voice(id: 43, name: "pm_alex"),
        Voice(id: 44, name: "pm_santa"),
        Voice(id: 45, name: "zf_xiaobei"), Voice(id: 46, name: "zf_xiaoni"),
        Voice(id: 47, name: "zf_xiaoxiao"), Voice(id: 48, name: "zf_xiaoyi"),
        Voice(id: 49, name: "zm_yunjian"), Voice(id: 50, name: "zm_yunxi"),
        Voice(id: 51, name: "zm_yunxia"), Voice(id: 52, name: "zm_yunyang"),
    ]

    static let grouped: [(label: String, voices: [Voice])] = [
        ("English (US female)", Array(all[0...10])),
        ("English (US male)", Array(all[11...19])),
        ("English (GB female)", Array(all[20...23])),
        ("English (GB male)", Array(all[24...27])),
        ("Other languages", Array(all[28...52])),
    ]

    static func voice(forID id: Int) -> Voice {
        all.indices.contains(id) ? all[id] : all[3]
    }
}
