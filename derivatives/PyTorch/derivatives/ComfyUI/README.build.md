# Building

This Dockerfile relies on the structure provided by [Vast.Ai Base images](https://github.com/vast-ai/base-image).

See the example below for building instructions.

```bash
docker buildx build \
    --no-cache \
    --platform linux/amd64 \
    --build-arg PYTORCH_BASE=vastai/pytorch:2.5.1-cuda-12.4.1 \
    --build-arg COMFYUI_REF=v0.3.10 \
    -t repo/image:tag --push
```
