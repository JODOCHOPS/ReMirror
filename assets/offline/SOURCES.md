# Bundled offline language data

- English → Simplified Chinese model: Firefox Translations `en` → `zh-Hans`,
  `base-memory`, version 3.0. Model, source and target SentencePiece vocabularies,
  and lexical shortlist are copied from Mozilla Remote Settings collection
  `main/translations-models-v2`. The exact attachment locations and SHA-256
  hashes are pinned in `tools/build_offline_assets.py`. Mozilla identifies the
  translation models as MPL 2.0. See `licenses/Mozilla-MPL-2.0.txt`.
- English-Chinese dictionary: ECDICT at commit
  `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b`. The SQLite file is built
  from `ecdict.csv` by `tools/build_offline_assets.py`. See
  `licenses/ECDICT-MIT.txt`.

The model and dictionary are bundled in the app. Translation and lookup run
locally; the Google, Baidu, and AI sources retain their existing network
behavior when chosen by the user.
