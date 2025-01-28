# Building

This Dockerfile relies on the structure provided by [Vast.Ai Base images](https://github.com/vast-ai/base-image).

See the example below for building instructions.

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg BASE_IMAGE=vastai/base-image:cuda-12.4.1-cudnn-devel-ubuntu22.04 \
    --build-arg PYTORCH_VERSION=2.5.1 \
    --build-arg PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 . \
    . -t repo/image:tag --push
```