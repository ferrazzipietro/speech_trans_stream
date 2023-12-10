# build frontend with node
FROM node:20-alpine AS frontend
RUN apk add --no-cache libc6-compat
WORKDIR /app

ARG DUMMY_ARG=1

COPY streaming-react-app .
RUN \
    if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
    elif [ -f package-lock.json ]; then npm ci; \
    elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i --frozen-lockfile; \
    else echo "Lockfile not found." && exit 1; \
    fi

RUN npm run build

# build backend on CUDA 
FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04 AS backend
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_MAJOR=20

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    wget \
    curl \
    # python build dependencies \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    sox libsox-fmt-all \
    # gradio dependencies \
    ffmpeg \
    # fairseq2 dependencies \
    libsndfile-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


# RUN apt-get install zlib1g-dev &&\
#     wget https://sourceforge.net/projects/libpng/files/libpng15/1.5.30/libpng-1.5.30.tar.gz &&\
#     tar -xzvf libpng-1.5.30.tar.gz &&\
#     cd libpng-1.5.30 &&\ 
#     ./configure --prefix=/usr/local/libpng &&\
#     make &&\
#     make install &&\
#     echo "Contents of /usr/local/lib:" && ls /usr/local/lib && \
#     echo "Contents of /usr/local/libpng/lib:" && ls /usr/local/libpng/lib && \
# #    ls /usr/local/lib/libpng* &&\
#     ldconfig &&\
#     cd ..
# ENV LD_LIBRARY_PATH=/usr/local/libpng/lib:

# RUN wget http://www.ijg.org/files/jpegsrc.v9a.tar.gz &&\
#     tar -xzvf jpegsrc.v9a.tar.gz &&\
#     cd jpeg-9a &&\ 
#     ./configure --prefix=/usr/local/libjpeg &&\
#     make &&\
#     make install 
# RUN cd .. &&\
#     echo "Contents of /usr/local/lib :" && ls /usr/local && \
#     echo "Contents of /usr/local/libjpeg/lib :" && ls /usr/local/libjpeg/lib && \
#     ls /usr/local/lib/libpng* &&\
#     ldconfig
# # ENV LD_LIBRARY_PATH=/usr/local/libpng/lib:

# RUN wget libjpeg62-turbo_2.0.6-4_amd64.deb &&\
#     tar -xzvf jpegsrc.v9a.tar.gz &&\
#     cd jpeg-9a &&\ 
#     ./configure --prefix=/usr/local/libjpeg &&\
#     make &&\
#     make install 
# RUN cd .. &&\
#     echo "Contents of /usr/local/lib :" && ls /usr/local && \
#     echo "Contents of /usr/local/libjpeg/lib :" && ls /usr/local/libjpeg/lib && \
#     ls /usr/local/lib/libpng* &&\
#     ldconfig
# ENV LD_LIBRARY_PATH=/usr/local/libpng/lib:

# RUN apt-get update &&\
#     apt-get -y install libjpeg62-turbo-dev &&\
#     apt-get install libjpeg8 libbodfile1

RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH
WORKDIR $HOME/app

RUN curl https://pyenv.run | bash
ENV PATH=$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH
ARG PYTHON_VERSION=3.10.12
RUN pyenv install $PYTHON_VERSION && \
    pyenv global $PYTHON_VERSION && \
    pyenv rehash && \
    pip install --no-cache-dir -U pip setuptools wheel

COPY --chown=user:user ./seamless_server ./seamless_server
# change dir since pip needs to seed whl folder
RUN cd seamless_server && \
    pip install fairseq2 &&\
#    pip install fairseq2 --pre --extra-index-url https://fair.pkg.atmeta.com/fairseq2/whl/nightly/pt2.1.1/cu118 && \
    pip install --no-cache-dir --upgrade -r requirements.txt
COPY --from=frontend /app/dist ./streaming-react-app/dist

WORKDIR $HOME/app/seamless_server
RUN --mount=type=secret,id=HF_TOKEN,mode=0444,required=false \ 
    huggingface-cli login --token $(cat /run/secrets/HF_TOKEN) || echo "HF_TOKEN error" && \
    huggingface-cli download meta-private/SeamlessExpressive pretssel_melhifigan_wm-final.pt  --local-dir ./models/Seamless/ || echo "HF_TOKEN error" && \
    ln -s $(readlink -f models/Seamless/pretssel_melhifigan_wm-final.pt) models/Seamless/pretssel_melhifigan_wm.pt || true;

USER root
RUN ln -s /usr/lib/x86_64-linux-gnu/libsox.so.3 /usr/lib/x86_64-linux-gnu/libsox.so
USER user
RUN ["chmod", "+x", "./run_docker.sh"]
CMD ./run_docker.sh


