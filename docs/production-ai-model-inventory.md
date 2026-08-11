# Production AI Model Inventory

> Updated: 2026-08-12
> Source of truth for current production AI routing.

## Current Model Assignments

- LLM base URL: `https://token.sensenova.cn/v1`
- LLM API key: store in production `.env`; do not commit key material
- LLM model: `sensenova-6.8-flash-lite`
- Transcription base URL: `https://api.groq.com/openai/v1`
- Transcription API key: store in production `.env`; do not commit key material
- Transcription model: `whisper-large-v3`
- Local dictionary database: offline lookup only; no AI generation
- Local Whisper: not used in current production path

## Verified Routes

| Feature | Route | Model / Engine | Evidence |
|---|---|---|---|
| Sentence translation | `POST /api/v1/stream/translate` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + live route |
| Sentence analysis | `POST /api/v1/stream/analyze` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + live route |
| Sense groups | `POST /api/v1/stream/sense-groups` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + live route |
| Word lookup | `POST /api/v1/stream/lookup-word` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + OpenAPI paths |
| Phrase lookup | `POST /api/v1/stream/lookup-phrase` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + OpenAPI paths |
| Sentence chat | `POST /api/v1/stream/chat/sentence` | `sensenova-6.8-flash-lite` | Production `.env` + backend prompt + live route |
| Transcription | `POST /api/v2/user-audio/submit-transcription` + job APIs | `whisper-large-v3` via Groq | Production `.env` + `transcribe.py` + OpenAPI paths |

## Notes

- `deepseek-chat` is not the current production LLM.
- `192.168.123.187:8001` hosts another service, but it is outside the current Echo Loop AI feature set verified here.
