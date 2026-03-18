# RFSuite Sound Generator

This folder is the legacy sound generation toolchain brought into the new framework repo.

What is here:

- `generate-all.bat`: generate the standard language/voice packs
- `generate-user.bat`: generate a custom user voice pack
- `generate-googleapi.py`: JSON-driven Google TTS builder
- `json/*.json`: prompt definitions for each language
- `soundpack/<lang>/<variant>/`: output folders for generated wav files

Notes:

- The checked-in `soundpack/` tree is directory scaffolding only. Audio files are created when the generator is run.
- The deploy pipeline already looks for generated files under `bin/sound-generator/soundpack/<lang>`.
- The generator expects Python plus its optional dependencies, including `sox` and `google-cloud-texttospeech`.
