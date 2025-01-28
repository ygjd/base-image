# Building

This Dockerfile relies on the structure provided by [Vast.Ai Base images](https://github.com/vast-ai/base-image).

See the example below for building instructions.

```bash
docker buildx build \
    --platform linux/amd64 \
    --build-arg PYTORCH_BASE=vastai/pytorch:2.5.1-cuda-12.1.1-py311 \
    --build-arg OPENWEBUI_REF=0.5.7 \
    --build-arg OLLAMA_REF=v0.5.7 \
    . -t repo/image:tag --push
```
