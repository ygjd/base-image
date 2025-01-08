ARG PYTORCH_BASE

FROM ${PYTORCH_BASE}

# Maintainer details
LABEL org.opencontainers.image.source="https://github.com/vastai/"
LABEL org.opencontainers.image.description="Stable Diffusion Fooocus image suitable for Vast.ai."
LABEL maintainer="Vast.ai Inc <contact@vast.ai>"

# Copy Supervisor configuration and startup scripts
COPY ./ROOT /

# Required or we will not build
ARG FOOOCUS_REF

RUN \
    [[ -n "${FOOOCUS_REF}" ]] || { echo "Must specify FOOOCUS_REF" && exit 1; } && \
    . ${DATA_DIRECTORY}venv/main/bin/activate && \
    # We have PyTorch pre-installed so we will check at the end of the install that it has not been clobbered
    torch_version_pre="$(python -c 'import torch; print (torch.__version__)')" && \
    # Install xformers while pinning to the inherited torch version.  Fail build on dependency resolution if matching version is unavailable
    pip install xformers torch==$PYTORCH_VERSION --index-url "${PYTORCH_INDEX_URL}" && \
    pip install onnxruntime-gpu insightface && \
    # Get Fooocus and install dependencies (torch should not be pinned to a specific version in the requirements.txt - If it is then our build will probably fail)
    cd "${DATA_DIRECTORY}" && \
    git clone https://github.com/lllyasviel/Fooocus && \
    cd ${DATA_DIRECTORY}Fooocus && \
    git checkout "${FOOOCUS_REF}" && \
    pip install --no-cache-dir \
        -r requirements_versions.txt && \
    # Download custom models into the build if you want them - None included in default build
    # wget -O ${DATA_DIRECTORY}Fooocus/models/checkpoints/model1.safetensors https://url.to.files/model1.safetensors && \
    # wget -O ${DATA_DIRECTORY}Fooocus/models/checkpoints/model2.safetensors https://url.to.files/model2.safetensors && \
    # Test 1: Verify PyTorch version is unaltered
    torch_version_post="$(python -c 'import torch; print (torch.__version__)')" && \
    [[ $pre_torch_version = $post_torch_version ]] || { echo "PyTorch version mismatch (wanted ${torch_version_pre} but got ${torch_version_post})" && exit 1; }
