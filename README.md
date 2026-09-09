Using TranslateGemma
https://ollama.com/library/translategemma

ollama run translategemma:12b

powershell -ExecutionPolicy Bypass -File .\translation_batch.ps1 -i "C:.\src\locales\en" -o ".\src\locales\uk" -sl "English" -sc "en" -tl "French" -tc "fr" -m "translategemma:12b"
