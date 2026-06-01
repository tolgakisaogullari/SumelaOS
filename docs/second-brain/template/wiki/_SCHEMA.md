# Second Brain Schema

> **Bu dosya kanonik format kaynağıdır.** Wiki'nin yapısı, page template'leri, frontmatter şeması ve isimlendirme kuralları burada tanımlıdır. `using-second-brain` skill bu dosyaya işaret eder ve detayları duplike etmez. Yeni bir projeye second-brain kurarken `_SCHEMA.md`'yi olduğu gibi kopyalayın — tamamen proje-bağımsızdır.

---

## 1. Üç Katmanlı Mimari

Karpathy'nin LLM Wiki pattern'i üç ayrık katmana dayanır:

```
docs/second-brain/
├── raw_sources/      ← IMMUTABLE. Kullanıcı tarafından sağlanan ham kaynaklar.
│   └── assets/       ← Görseller, diyagramlar, indirilen ekler.
├── artifacts/        ← IMMUTABLE. LLM tarafından üretilmiş ama write-once dokümanlar.
│   ├── plans/        ← writing-plans skill çıktıları.
│   └── specs/        ← brainstorming skill çıktıları.
└── wiki/             ← LIVE. LLM tarafından sürekli güncellenen sentez katmanı.
    ├── archive/      ← Wiki'den emekliye ayrılan ama silinmeyen sayfalar.
    ├── insights/     ← Query write-back ile kaydedilen analizler.
    ├── summaries/    ← Her raw_source dosyasının LLM-üretimi özet sayfası.
    ├── _INDEX.md          ← Special: insan-optimized içerik kataloğu.
    ├── _LOG.md            ← Special: kronolojik aktivite kaydı.
    ├── _SCHEMA.md         ← Special: bu dosya.
    ├── _SEARCH_INDEX.md   ← Special: agent-optimized arama indeksi.
    └── *.md               ← Sentez sayfaları (entity, concept, decision, core).
```

**Katman kuralları:**
- `raw_sources/`: LLM bu klasörden **okur**, **asla yazmaz**. Ham ve immutable.
- `artifacts/`: LLM bu klasöre **yazar** (skill çıktısı olarak), sonra **dokunmaz**. Write-once.
- `wiki/`: LLM bu klasörü **sürekli günceller**. Sentez, çelişki çözümü, cross-reference burada yaşar.

---

## 2. Page Tipleri

Her wiki sayfası bir tip altına düşer. Tip, frontmatter'da `type:` alanıyla belirtilir.

| Type | Açıklama | Örnek |
|---|---|---|
| `core` | Projenin temel referans sayfaları | `architecture-and-stack`, `developer-onboarding`, `active-project-context` |
| `entity` | Sistemdeki bir varlık veya domain nesnesi | `domain-entities`, `user-model`, `payment-flow` |
| `concept` | Bir kavram, pattern veya alt sistem | `api-registry`, `tech-debt-and-known-issues`, `caching-strategy` |
| `decision` | Mimari karar kayıtları (ADR-style) | `architecture-decisions` |
| `insight` | Query write-back'ten kaydedilen analizler | `insights/2026-04-08-cache-vs-redis-comparison` |
| `archive` | Aktif kullanımdan çıkmış ama saklanan içerik | `archive/sprint-history` |
| `source-summary` | Bir raw_source dosyasının özeti | `summaries/karpathy-llm-wiki` |

**Special files (frontmatter ALMAZ):** `_INDEX.md`, `_LOG.md`, `_SCHEMA.md`, `_SEARCH_INDEX.md`

---

## 3. YAML Frontmatter Şeması

Her wiki sayfası (special files HARİÇ) şu frontmatter ile başlamak ZORUNDADIR:

```yaml
---
type: entity              # zorunlu — page tipi (yukarıdaki tablodan)
tags: [domain, auth]      # zorunlu — minimum 1 etiket; arama ve Dataview için
date_created: 2026-04-08  # zorunlu — ISO 8601 (YYYY-MM-DD)
date_updated: 2026-04-08  # zorunlu — son güncelleme tarihi
sources_referenced: 0     # opsiyonel — bu sayfanın türetildiği kaynak sayısı
status: active            # opsiyonel — active | archive | deprecated
---
```

**Type-spesifik ek alanlar:**

```yaml
# decision tipi için:
---
type: decision
decision_id: AD-12        # zorunlu — Architecture Decision ID
decision_status: accepted # accepted | superseded | deprecated
superseded_by: AD-15      # opsiyonel — eğer superseded ise
---

# insight tipi için:
---
type: insight
query_origin: "Redis vs in-memory cache karşılaştırması"  # zorunlu — kaynak soru
related_pages: [caching-strategy, performance]
---

# source-summary tipi için:
---
type: source-summary
source_path: ../../raw_sources/karpathy-llm-wiki.md  # zorunlu
source_type: article | book | meeting | code-snapshot | external
ingested_date: 2026-04-08
---
```

---

## 4. İsimlendirme Kuralları

| Konum | Format | Örnek |
|---|---|---|
| Wiki sayfaları | `kebab-case.md` | `domain-entities.md`, `tech-debt-and-known-issues.md` |
| Artifact'lar (plans/specs) | `YYYY-MM-DD-feature-name.md` | `2026-04-08-second-brain-restructure.md` |
| Insight'lar | `insights/YYYY-MM-DD-topic.md` | `insights/2026-04-08-cache-comparison.md` |
| Archive sayfaları | `archive/<original-name>.md` | `archive/sprint-history.md` |
| Source summaries | `summaries/<source-slug>.md` | `summaries/karpathy-llm-wiki.md` |
| Web-captured sources | `raw_sources/YYYY-MM-DD-<slug>.md` | `raw_sources/2026-04-11-react-native-hls.md` |

**Kurallar:**
- Sadece küçük harf, tire ile ayrılmış (`kebab-case`)
- Türkçe karakter YOK (ı→i, ş→s, ç→c, ğ→g, ö→o, ü→u)
- Boşluk YOK
- Tarihli dosyalarda tarih HER ZAMAN başta

---

## 5. Cross-Reference Konvansiyonu

Wiki içi referanslar için **iki format** kullanılır:

### Obsidian wikilink (tercih edilen)
```markdown
[[domain-entities]]                    # uzantısız, kebab-case dosya adı
[[domain-entities|Domain Modeli]]      # özel etiket
[[architecture-decisions#AD-05]]       # belirli başlığa
```

Obsidian wikilink'leri vault içinde dosya adına göre çözülür — yol bilmeye gerek yok. Bu yüzden dosyalar farklı klasörlere taşınsa bile çalışır.

### Standard markdown link (relatif yol)
```markdown
[domain-entities](./domain-entities.md)
[plan dosyası](../artifacts/plans/2026-04-08-second-brain-restructure.md)
```

**Kullanım kuralı:**
- Wiki içi referanslar → Obsidian wikilink (`[[...]]`)
- Wiki dışı referanslar (artifacts, raw_sources, .sumela) → Standard markdown link (relatif yol)
- Asla mutlak yol kullanma

---

## 6. `_LOG.md` Entry Formatı

`_LOG.md` parse-friendly olmak ZORUNDADIR. Karpathy'nin önerdiği format:

```markdown
## [YYYY-MM-DD] type | topic

- Bullet point açıklama
- İkinci bullet
- Etkilenen wiki sayfaları: [[page-1]], [[page-2]]
- Commit (varsa): `abc1234`
```

**Type whitelist (tek kelime, küçük harf):**
| Type | Ne zaman |
|---|---|
| `ingest` | Yeni raw_source işlendi, wiki sayfaları güncellendi |
| `query` | Kullanıcı sorusu cevaplandı ve insight wiki'ye kaydedildi |
| `lint` | Wiki sağlık kontrolü yapıldı |
| `code-commit` | Bir geliştirme branch'i finish edildi, wiki yansıması yapıldı |
| `decision` | Yeni mimari karar kaydedildi (decision page güncellendi) |
| `evolve` | Self-improvement queue review (`/evolve`) — bir IMP entry applied/superseded oldu |
| `migration` | Wiki yapısal değişikliği (klasör taşıma, format güncelleme) |

**Parse doğrulaması:**
```bash
grep "^## \[" docs/second-brain/wiki/_LOG.md | tail -10
```
Bu komut, son 10 entry'i listelemeli. Hiçbir entry parse edilmeyen formatla yazılmamalıdır.

---

## 7. `_INDEX.md` Yapısı

`_INDEX.md` content-oriented bir kataloğdur. Her aktif wiki sayfası bir satır olarak listelenir:

```markdown
[[page-name]] - One-line summary. (Sources: N)
```

**Kategoriler (öneri):**
- **Core Pages** — `type: core` olan sayfalar
- **Entity & Concept Pages** — `type: entity` veya `type: concept`
- **Decision Records** — `type: decision`
- **Source Summaries** — `type: source-summary` (her raw_source'un özet sayfası)
- **Insights** — `type: insight` (Query write-back kayıtları)
- **Archive** — `type: archive` (referans için)
- **Artifacts (External)** — plans/ ve specs/ klasörlerine pointer'lar (tek satır, standard markdown link)

**Kural:** `_INDEX.md` her session başında okunur, dolayısıyla **kompakt** olmalı. Arşiv listeleri tek satıra indirgenmeli.

---

## 8. Page Template'leri

### Core Page Template

```markdown
---
type: core
tags: [<primary-concern>, <project-name>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
status: active
---

# [Sayfa Başlığı] — [Proje Adı]

> **Bu dosyanın amacı ve okunma sıklığı.** (Ör: "Her session başında okunur.")

---

## [Bölüm 1]
İçerik...

## [Bölüm 2]
İçerik...

---

## Referanslar
- [[related-page-1]]
- [[related-page-2]]
```

### Entity Page Template

```markdown
---
type: entity
tags: [domain, <feature-area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
sources_referenced: 0
status: active
---

# [Entity Name]

## Tanım
Bu varlık nedir, ne işe yarar?

## Alanlar / Özellikler
| Alan | Tip | Açıklama |
|---|---|---|

## İlişkiler
- `[[other-entity]]` ile bire-çok
- `[[third-entity]]` ile çoğa-çok

## Kullanım Yerleri
- `[[api-registry#endpoint-X]]`
- `[[caching-strategy]]`

## Kaynaklar
- `../artifacts/specs/YYYY-MM-DD-feature-design.md`
```

### Decision Page Template (Architecture Decision Record)

```markdown
---
type: decision
decision_id: AD-XX
decision_status: accepted
tags: [architecture, <area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
---

## AD-XX: [Karar Başlığı]

**Karar:** Tek cümleyle ne karar verildi.

**Bağlam:** Neden bu karara ihtiyaç duyuldu? Hangi sorunlar mevcuttu?

**Alternatifler:** Hangi seçenekler değerlendirildi?
- Option A: ... (Pros / Cons)
- Option B: ... (Pros / Cons)

**Sonuç:** Karar nelere yol açtı? Hangi sayfalarda etkisi var?
- `[[entity-X]]` üzerinde değişiklik
- `[[api-registry]]` yeni endpoint

**Kaynaklar:** `../artifacts/specs/YYYY-MM-DD-design.md`
```

### Insight Page Template (Query Write-Back)

```markdown
---
type: insight
query_origin: "Kullanıcının sorduğu orijinal soru"
tags: [insight, <area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
related_pages: [page-1, page-2]
---

# [Insight Başlığı]

## Soru
[Kullanıcının orijinal sorusu]

## Cevap / Sentez
[3+ wiki sayfasını birleştiren analiz]

## Bağlantılı Sayfalar
- `[[page-1]]` — bu açıdan ilgili
- `[[page-2]]` — bu açıdan ilgili

## Açık Sorular / Follow-up
- ?
```

### Source Summary Page Template

```markdown
---
type: source-summary
source_path: ../../raw_sources/<filename>
source_type: article
ingested_date: YYYY-MM-DD
tags: [source, <topic>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
---

# [Source Başlığı]

## Özet
Bu kaynak ne hakkında? 3-5 cümle.

## Anahtar Çıkarımlar
- Çıkarım 1
- Çıkarım 2

## Wiki'ye Yansıma
Bu kaynak hangi wiki sayfalarını güncelledi?
- `[[page-1]]` — şu kısım eklendi
- `[[page-2]]` — şu çelişki not edildi

## Çelişkiler
Bu kaynak mevcut wiki ile çelişiyor mu? Nasıl çözüldü?
```

---

## 9. Çelişki Yönetimi

Karpathy pattern'inin temel değeri: yeni kaynaklar eski iddiaları çürüttüğünde **wiki'de açıkça not edilir, üzerine yazılmaz**.

**Örnek:**
```markdown
## Cache Stratejisi

~~Eski iddia (2026-03-15): Tüm endpoint'ler Redis ile cache'lenmeli.~~
**Çürütüldü (2026-04-02):** [2026-04-02-cache-analysis-design](../artifacts/specs/2026-04-02-cache-analysis-design.md) → 
sadece read-heavy endpoint'ler Redis'e konmalı; write-heavy endpoint'lerde cache invalidation maliyeti faydanın üzerinde.
```

Çelişkiler `_LOG.md`'a `decision` entry'si olarak da kaydedilir.

---

## 10. Special Files Sözleşmesi

Bu dört dosya **frontmatter almaz** ve özel kurallara tabidir:

| Dosya | Kural |
|---|---|
| `_INDEX.md` | Her session başında okunur. Maksimum ~100 satır. Sadece pointer'lar, içerik yok. |
| `_LOG.md` | Append-only. Sadece yeni entry'ler eklenir, eskileri DEĞİŞTİRİLMEZ (tarihsel doğruluk). |
| `_SCHEMA.md` | Bu dosya. Sadece schema değişirken güncellenir. |
| `_SEARCH_INDEX.md` | Agent-optimized arama indeksi. Her ingest/code-commit/lint'te güncellenir. Detay: Section 13. |

**Tarihsel doğruluk kuralı:** `_LOG.md` immutable history sayılır. Bir entry yazıldıktan sonra path veya isim değişiklikleri için entry'yi yeniden yazmak yasaktır — bunun yerine yeni bir `migration` entry'si eklenir.

**Takım eşzamanlılık modeli (multi-developer merge stratejisi):**
- `_LOG.md` → append-only olduğu için repo kökündeki `.gitattributes`'te `merge=union` ile işaretlidir: farklı geliştiricilerin eşzamanlı log eklemeleri conflict yerine birleşir. (Rotasyon/`migration` istisnası: bkz. `.gitattributes` notları.)
- `_improvement-queue/` → her sinyal ayrı `IMP-*.md` dosyası olduğu için eşzamanlı yakalama hiç conflict üretmez (merge driver gerekmez).
- `active-project-context.md` → yapılandırılmış prose; `union` UYGULANMAZ (bölümleri bozardı). Paylaşılan sprint state'tir, kişisel scratchpad değil — per-developer aktif iş "Active Work" bölümünde `@isim`/branch ile ayrı satırlarda tutulur, geçici detay session summary'ye yazılır. Gerçek conflict elle çözülür.

---

## 11. `_LOG.md` Rotasyon Mekanizması

`_LOG.md` append-only olduğu için proje büyüdükçe şişer. Agent'ın session başında lightweight grep kullanması bu sorunu hafifletir, ancak lint sırasında tam dosya okunabilir.

**Rotasyon kuralı (opsiyonel, ~50+ entry'de devreye girer):**
1. `_LOG.md`'deki 6 aydan eski entry'ler `archive/_LOG-YYYY.md` dosyasına taşınır.
2. Taşıma bir `migration` entry'si olarak loglanır.
3. Arşivlenen log dosyaları immutable kalır.
4. Rotasyon sadece lint sırasında önerilir, otomatik çalışmaz.

---

## 12. Obsidian Ekosistem Rehberi (Karpathy Tips)

Wiki, Obsidian vault olarak kullanılmak üzere tasarlanmıştır. Aşağıdaki ayar ve eklentiler önerilir:

**Temel Ayarlar:**
- **Files and links → Attachment folder path:** `raw_sources/assets/` (görseller merkezi bir yere indirilsin)
- **Files and links → New link format:** `Relative path to file` (wikilink uyumu)

**Önerilen Eklentiler:**
- **Graph View** (core) — Wiki'nin şeklini görselleştirir; hub sayfaları ve orphan'ları tespit etmeye yardımcı olur.
- **Dataview** — YAML frontmatter üzerinden dinamik tablolar ve listeler üretir (ör. `TABLE date_updated, type FROM "wiki" SORT date_updated DESC`).
- **Obsidian Web Clipper** — Web makalelerini markdown'a dönüştürüp `raw_sources/` altına kaydetmeye yarar.

**Opsiyonel:**
- **Marp** — Markdown tabanlı sunum formatı. Wiki içeriğinden doğrudan slayt üretilebilir.

---

## 13. Ölçekleme — `_SEARCH_INDEX.md` (Agent-Optimized Arama)

Wiki büyüdükçe `_INDEX.md` tek başına yetersiz kalır. Bu sorunu **sıfır bağımlılıkla** (script yok, runtime yok, binary yok) çözen mekanizma: `_SEARCH_INDEX.md`.

### İki Aşamalı Arama Stratejisi

| Aşama | Ne | Nasıl |
|---|---|---|
| 1. Index tarama | Agent `_SEARCH_INDEX.md` tablosunu okur | Query terimlerini `Key Terms` ve `Tags` sütunlarıyla eşleştirir |
| 2. Hedefli okuma | Sadece eşleşen sayfaları okur | Tam sayfa içeriğine erişir, cevabı sentezler |

Bu strateji wiki yüzlerce sayfaya ulaşsa bile çalışır: 200 sayfa × ~120 karakter/satır = ~24KB — herhangi bir LLM context'ine rahatça sığar.

### `_SEARCH_INDEX.md` Yapısı

```markdown
| Page | Type | Tags | Key Terms | Summary |
|---|---|---|---|---|
| [[page-name]] | core | tag1, tag2 | term1, term2, term3 | Tek satırlık açıklama |
```

**Sütun kuralları:**
- **Page:** Obsidian wikilink (tıklanabilir)
- **Type:** `_SCHEMA.md` Section 2'deki page type'larından biri
- **Tags:** Frontmatter `tags` alanının kopyası (virgülle ayrık)
- **Key Terms:** Sayfanın içeriğinden çıkarılan 5-15 arama terimi — teknik kavramlar, teknoloji isimleri, ID'ler (ör. `AD-01..AD-12`, `TD-01..TD-14`), domain terimleri. **Tags'ten farklıdır:** tags kategorize eder, key terms arama eşleştirmesi sağlar.
- **Summary:** Tek satır, maksimum ~100 karakter

### Bakım Kuralları

- `_SEARCH_INDEX.md` her **ingest**, **code-commit** ve **lint** operasyonunda güncellenir.
- Yeni wiki sayfası → yeni satır eklenir.
- Sayfa arşive taşınırsa → satır `archive/` prefix'i ile güncellenir.
- Sayfa silinmezse (NEVER delete — always archive) → satır asla kaldırılmaz.
- `_INDEX.md` ile tutarlılık lint sırasında kontrol edilir: her `_INDEX.md` entry'si `_SEARCH_INDEX.md`'de de olmalı ve vice versa.

### Opsiyonel: Üst Tier Arama Katmanları (~500+ sayfa)

Çok büyük wiki'ler veya kod-yoğun projeler için `_SEARCH_INDEX.md` tek başına yetersiz kalır. Önerilen yol haritası:

- **Tier 1 — Qdrant** (semantic session memory): Ollama embedding (`qwen3-embedding:0.6b`) + local Qdrant. "Geçen hafta ne konuştuk?" tipi soruları çözer.
- **Tier 2 — Graphify** (kod yapısı): AST + call graph. Function/class lookup ve impact analysis için.
- Her iki tier de skill seviyesinde routing'e bağlanır (`using-second-brain` skill, REASONING AID workflow).

---

## 14. Special Files Tam Listesi

Güncel special files (frontmatter ALMAZ):

| Dosya | Amaç | Bakım Sıklığı |
|---|---|---|
| `_INDEX.md` | İnsan-optimized içerik kataloğu (Obsidian navigasyonu) | Her ingest/code-commit |
| `_LOG.md` | Kronolojik append-only aktivite kaydı | Her operasyon |
| `_SCHEMA.md` | Kanonik format kuralları | Schema değişikliğinde |
| `_SEARCH_INDEX.md` | Agent-optimized arama indeksi (tag + key term tablosu) | Her ingest/code-commit/lint |
| `_improvement-queue/` | Self-improvement öneri kuyruğu — dizin, her sinyal kendi `IMP-*.md` dosyası (sinyal yakalama + onay + challenge) | Her sinyal yakalandığında yeni dosya |

---

## 15. Self-Improvement Queue (`_improvement-queue/`)

Agent'ın session'lar arası öğrenebilmesi için kullanılan persistent öneri kuyruğudur. `self-improvement-curator` skill tarafından yönetilir, `/evolve` slash command ile review edilir. Kuyruk bir **dizindir** (her sinyal kendi `IMP-*.md` dosyası) — takımda eşzamanlı yakalama merge-conflict üretmesin diye. Bkz. `_improvement-queue/README.md`.

### 15.1 Amaç

Karpathy wiki pattern'i **bilgi** için çelişki toleransı sağlar; `_improvement-queue/` ise **agent'ın kendi davranış/kural öğrenmesi** için aynı pattern'i uygular. Hedef:
- Session'da yakalanan düzeltme/onay/karar sinyallerini kaybetmeden kuyruğa yazmak
- Onay kapısı olmadan rule/skill/wiki'ye yazmayı kesinlikle önlemek
- Eski öğrenilmiş kuralların **challenge edilmesine + supersede edilmesine** izin vermek
- Farklı LLM provider'ların öğrenmelerinin geçmişini saklamak (`provider_context` alanı)

### 15.2 Dosya Yapısı (Dizin — Her Sinyal Kendi Dosyası)

Kuyruk **monolitik bir dosya değil**, bir dizindir: `_improvement-queue/`. Her sinyal
**kendi dosyasıdır**. Takımda birden çok geliştiricinin agent'ı aynı anda sinyal
yakalar — her sinyal ayrı dosya olduğu için eşzamanlı yakalamalar **merge-conflict
üretmez**. Paylaşılan `IMP-NNN` sayacı **YOKTUR** (paylaşılan sayaç eşzamanlı
yakalamada çakışır). Durum (pending/applied/...) her dosyanın frontmatter'ında
yaşar; status değişimi tek küçük dosyaya edit'tir, monolitin çekişmeli yeniden
yazımı değil.

**Dosya adı = ID:** `IMP-YYYYMMDD-<short>.md`
- `IMP-` prefix (greppable) + `YYYYMMDD` capture tarihi (kronolojik) + `<short>`
  (4 küçük-harf base36, lokal üretilir, koordinasyon yok). Agent yazmadan önce
  dosya adının var olmadığını doğrular; nadir çakışmada yeniden üretir. "İnsan-dostu
  GUID": sayaçsız çakışmasız, ama review'da söylenebilir ("IMP-20260601-a3f8 uygula").
- `id:` frontmatter alanı dosya adının kök adına **eşit olmalı**. Dosya adı tek
  doğruluk kaynağıdır; hiçbir yerde artırılacak sayaç yoktur.
- Yalnızca `IMP-*.md` dosyaları entry'dir. `README.md` entry değildir; tüm durum
  sorguları `IMP-*.md` glob'lar (README sayılmaz).

Frontmatter taranabilir metadata'yı tutar; gövde insan-okunur prose'u (`## Proposed
Change`, `## Evidence`) tutar:

```markdown
---
id: IMP-20260414-a3f8
detected: 2026-04-14
signal_type: correction
scope: rule
target: .sumela/rules/backend_standards.md
provider_context: claude-opus-4-8
confidence: high
status: pending
---

## Proposed Change

EF Core queries with 3+ joins must explicitly declare `AsSplitQuery()`.

## Evidence

Session 2026-04-14: N+1 + Cartesian explosion yakalandı; kullanıcı AsSplitQuery'yi onayladı.
```

Status değiştiğinde dosya **yerinde** düzenlenir (taşınmaz): `applied`/`superseded`/
`rejected` entry'ler **silinmez** (tarihsel doğruluk), sadece frontmatter'ları güncellenir.

### 15.3 Entry Şeması (Zorunlu Alanlar)

`proposed_change` ve `evidence` gövdede (`## Proposed Change` / `## Evidence`
başlıkları altında) yaşar; aşağıdaki alanlar frontmatter'dadır:

| Alan | Tip | Açıklama |
|---|---|---|
| `id` | `IMP-YYYYMMDD-<short>` | Dosya adının kök adı. Sayaç yok, asla yeniden kullanma. |
| `detected` | `YYYY-MM-DD` | Sinyalin yakalandığı tarih |
| `signal_type` | enum | `correction` \| `confirmation` \| `decision` \| `friction` \| `challenge` |
| `scope` | enum | `rule` \| `skill` \| `wiki` \| `schema` \| `active-context` |
| `target` | path | Dokunulacak dosyanın relative path'i. `scope: rule` için default `.sumela/rules/<topic>.md` (portable, IDE-agnostic). |
| `provider_context` | string | Sinyali yakalayan model (`claude-opus-4-8`, `claude-sonnet-4-6`, vs.) |
| `confidence` | enum | `high` \| `medium` \| `low` (bkz. 15.5) |
| `status` | enum | `pending` \| `applied` \| `superseded` \| `rejected` |

**Duruma göre ek frontmatter alanları (status değişince yerinde eklenir):**
- `applied` → `applied: YYYY-MM-DD`, `last_validated: YYYY-MM-DD`, `challenges: [IMP-ID, ...]`
- `superseded` → `superseded_by: IMP-ID`, `superseded_at: YYYY-MM-DD`
- `rejected` → `rejected_at: YYYY-MM-DD`, `rejection_reason: text`
- `pending` (deferred at `/evolve`) → `deferred_at: YYYY-MM-DD` (status stays `pending`)
- `signal_type: challenge` → `supersedes: IMP-ID` (hangi applied entry'i sorguluyor)

### 15.4 Sinyal Tipleri (Ne Yakalanır?)

| Type | Ne zaman |
|---|---|
| `correction` | Kullanıcı "hayır, öyle değil" / "bir daha böyle yapma" / "şunu kullanma" dediğinde |
| `confirmation` | Kullanıcı tartışmalı bir seçimi onayladığında ("evet, tam da böyle", "doğru seçim") |
| `decision` | Brainstorming/ULTRATHINK sırasında mimari karar alındığında |
| `friction` | Aynı hata/soru 2+ kez tekrar ettiğinde (pattern tespiti) |
| `challenge` | Mevcut `applied` entry ile çelişen yeni kanıt bulunduğunda |

### 15.5 Confidence Thresholds (Sessiz Kalmayı Önlemek İçin)

`self-improvement-curator`'ın thresholdu çok yükseğe çekip hiç yazmaması kabul edilemez. Kural:

- **`high`**: Kullanıcı açıkça doğruladı VEYA reddetti VEYA 2+ kez aynı düzeltmeyi yaptı → **HER ZAMAN** kuyruğa yazılır.
- **`medium`**: Tartışmalı ama kanıt somut (kod/log/dosya referansı var) → **HER ZAMAN** kuyruğa yazılır, review'da kullanıcıya "emin değilim" notuyla sunulur.
- **`low`**: Sadece sezgi, somut kanıt yok → **YAZILMAZ** (gürültüyü önlemek için).

**Kural:** Şüpheye düşersen `medium` seç, `low`'a kaçma. Review kapısı kullanıcıyı koruyor — agent'ın iş yükünü azaltmak uğruna sinyal kaçırmak kabul edilemez.

### 15.6 Challenge & Supersede Akışı (Eski Öğrenileni Güncelleme)

Farklı provider/zaman farklı karar verebilir. Agent yeni session'da mevcut bir `applied` entry ile çelişen somut kanıt bulursa:

1. **Yeni bir entry oluşturur**, `signal_type: challenge`, `supersedes: <IMP-ID>` alanıyla orijinale referans verir.
2. Entry `pending` olarak kuyruğa yazılır — **asla otomatik uygulanmaz**.
3. `/evolve` review'da kullanıcı challenge'ı onaylarsa:
   - Orijinal entry dosyasının frontmatter'ı yerinde güncellenir: `status: superseded`, `superseded_by: <yeni-IMP-ID>`, `superseded_at` eklenir
   - Yeni entry `status: applied` olur, ilgili dosyaya uygulanır
   - `_LOG.md`'ye `decision` entry'si: *"IMP-20260601-a1b2 superseded by IMP-20260714-c3d4 — reason: ..."*
4. Orijinal entry dosyası **silinmez** — sadece frontmatter'ı `superseded` yapılır, dosya yerinde kalır (tarihsel doğruluk).

### 15.7 Proaktif Re-validation

Session başında `using-second-brain` eager-load içinde:
- Pending entry sayısı raporlanır (sayı > 0 ise kullanıcıya *"N öneri onay bekliyor, /evolve ile bakabilirsin"* denir)
- Son 5 applied entry'nin özeti gösterilir (context bütçesi bu kadar) — dizini `grep -l "^status: applied" IMP-*.md` ile tarayıp tarihe göre son 5'i al
- **Re-validation pulse**: Son 90 günde `last_validated` güncellenmemiş applied entry'lerden rastgele 1 tanesi seçilir → agent session boyunca bu entry'nin hâlâ geçerli olup olmadığına dair pasif dikkat eder. Çelişki görürse otomatik `challenge` sinyali açar.

### 15.8 Onay Modeli (Çift Onay Kuralı)

| Scope | Onay Modeli |
|---|---|
| `wiki` (sentez sayfaları) | Tek onay + diff preview |
| `active-context` | Tek onay |
| `skill` (yeni) | Tek onay + `writing-skills` skill'i zorunlu |
| `skill` (mevcut edit) | Tek onay + diff + etkilenen workflow listesi |
| `rule` (`.sumela/rules/*.md`) | **Çift onay:** "bu kural yazılsın mı?" → sonra "uygula?" |
| `schema` (`_SCHEMA.md`) | **Çift onay** + manuel review zorunlu |

### 15.9 Hijyen & Arşivleme

- `_improvement-queue/` 500+ entry olursa `superseded` ve `rejected` dosyaları `_improvement-queue/archive/YYYY/` alt dizinine taşınır (dosyalar silinmez)
- `applied` entry'ler **asla** arşivlenmez (aktif öğrenme, challenge edilebilir olmalı)
- Arşivleme bir `migration` log entry'si ile kayıt altına alınır
- Session başı eager-load sadece `pending` + son 5 `applied` okur (context bütçesi); durum dizini `grep -l "^status: <durum>" IMP-*.md` ile taranır

### 15.10 `_LOG.md` Entegrasyonu

Aşağıdaki olaylar `_LOG.md`'ye `decision` entry'si olarak yazılır:
- Bir IMP entry `applied` olduğunda
- Bir IMP entry `superseded` olduğunda (challenge onayı)
- Bir IMP entry `rejected` olduğunda (opsiyonel, sadece rule/schema scope için)

Format:
```markdown
## [2026-04-14] decision | IMP-20260414-a3f8 applied: AsSplitQuery rule added
- Scope: rule → .sumela/rules/backend_standards.md
- Provider: claude-opus-4-8
- Challenges: none
```

## 16. Scale Playbook (Wiki Büyüme Yol Haritası)

Wiki büyüdükçe search stack değişir. Aşağıdaki tabloya göre ilerleyin:

| Wiki Size | Search Stack | Action Required |
|---|---|---|
| 0-100 pages | `_SEARCH_INDEX.md` + grep | None; current stack sufficient |
| 100-300 pages | Same | Audit `_SEARCH_INDEX.md` parity more frequently |
| 300-1000 pages | `_SEARCH_INDEX.md` + grep + **Graphify** + **Qdrant (chat_history)** | Install `graphify` CLI, deploy local Qdrant + Ollama embeddings; wire `auto-update-memory.py` |
| 1000+ pages | Qdrant + Graphify primary; `_SEARCH_INDEX.md` secondary | Multi-collection Qdrant (chat_history + wiki_pages + code_chunks); enriched payloads |

Threshold check: invoked during lint workflow (count `*.md` in wiki/ non-recursively).

## 17. Image Reading Workflow (Karpathy Image Pattern)

LLM'ler (Claude dahil) genellikle inline görselleri tek geçişte okuyamaz. Karpathy'nin önerdiği pattern, bu wiki'de şöyle uygulanır:

1. Agent önce kaynak markdown metnini okur (tam metinsel bağlam kurulur).
2. Agent, görsel referanslarını belirler (`![[...]]` veya `![](../raw_sources/assets/...)`).
3. Agent, native image-read yeteneği ile görselleri ayrıca görüntüler.
4. Agent, metin + görsel içeriğini source-summary sayfasında birleştirir.

**Storage kuralı:** tüm görsel asset'leri `raw_sources/assets/` altında tutulur (bkz. Section 12 "Obsidian Ekosistem Rehberi"). Obsidian "Attachment folder path" ayarı bu dizine eşlenmiş olmalıdır.
