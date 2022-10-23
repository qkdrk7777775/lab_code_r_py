FROM ubuntu:22.04
MAINTAINER CJCHO <qkdrk7777775@gmail.com>

# error remove
ENV DEBIAN_FRONTEND noninteractive

ENV DEFAULT_USER=conda
ENV DEFAULT_PASSWD=conda
ENV RSTUDIO_PASSWD=rstudio
ENV PATH=/usr/lib/rstudio-server/bin:$PATH

#create user
RUN useradd -ms /bin/bash rstudio -g root -G sudo 
RUN echo "rstudio:${RSTUDIO_PASSWD}" | chpasswd

RUN useradd -ms /bin/bash ${DEFAULT_USER} -g root -G sudo
RUN echo "${DEFAULT_USER}:${DEFAULT_PASSWD}" | chpasswd

# update 
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install apt-utils vim -y

SHELL ["/bin/bash", "--login", "-c"]
WORKDIR  /home/rstudio

# hangul encoding
RUN apt-get install -y locales locales-all
RUN locale-gen ko_KR.UTF-8
ENV LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8
ENV TZ=Asia/Seoul

#install miniconda
RUN apt-get update --fix-missing &&\
	apt-get install -y wget bzip2 curl git && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

RUN wget --quiet  https://repo.anaconda.com/miniconda/Miniconda3-py38_4.12.0-Linux-x86_64.sh  -O ~/miniconda.sh && \
	/bin/bash ~/miniconda.sh -b -p /opt/conda && \
	rm ~/miniconda.sh && \
	/opt/conda/bin/conda clean --all && \
	ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
	echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc

ENV PATH=$PATH:/opt/conda/condabin/conda
	
RUN conda update -n base -c defaults conda --quiet --yes

## create condaenv
RUN conda create -n "${DEFAULT_USER}" python=3.9 -y 
RUN echo "conda activate ${DEFAULT_USER}" >> ~/.bashrc

RUN conda activate ${DEFAULT_USER} && \
	 conda install ipykernel jupyterlab jupyter --quiet --yes && \ 
	 jupyter notebook --generate-config && \

	/opt/conda/envs/${DEFAULT_USER}/bin/python -c 'from notebook.auth import passwd; \
	import os; pwd=os.getenv("DEFAULT_PASSWD"); \
	pw=passwd(pwd,algorithm="sha1"); \
	print(f"c.NotebookApp.password=u\"{pw}\"")' \
	>> /root/.jupyter/jupyter_notebook_config.py && \
	jupyter lab clean 

EXPOSE 8888
RUN echo "c.NotebookApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_notebook_config.py
RUN echo "c.NotebookApp.notebook_dir = '/home/${DEFAULT_USER}'" >> /root/.jupyter/jupyter_notebook_config.py
RUN echo "c.NotebookApp.allow_root = True" >> /root/.jupyter/jupyter_notebook_config.py
RUN echo "c.NotebookApp.open_browser = False" >> /root/.jupyter/jupyter_notebook_config.py

# install Rstudio server(http://cran.rstudio.com/bin/linux/ubuntu/)
## install R
RUN apt-get update -y && apt-get upgrade -y 
RUN apt-get install gdebi-core -y
RUN apt install  --no-install-recommends software-properties-common dirmngr  -y
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc 
RUN add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" 
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt install --no-install-recommends r-base -y

# install rstudio-server
RUN wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2022.07.2-576-amd64.deb -O ~/rstudio-server.deb && \
	gdebi ~/rstudio-server.deb  -n && \
	rm ~/rstudio-server.deb

EXPOSE	8787

ENV R_BIN=/usr/bin/R
RUN echo "rsession-which-r=${R_BIN}" >/etc/rstudio/rserver.conf

RUN echo "[*]" >> /etc/rstudio/logging.conf &&\
	echo "log-level=warn" >> /etc/rstudio/logging.conf


# install shiny server(https://www.rstudio.com/products/shiny/download-server/ubuntu/)
RUN wget https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.19.995-amd64.deb -O ~/shiny-server.deb && \
	gdebi ~/shiny-server.deb -n && \ 
	rm ~/shiny-server.deb

# install code server(https://github.com/coder/code-server)
RUN curl -fsSL https://code-server.dev/install.sh | sh
RUN mkdir  -p /root/.config/code-server

RUN echo "bind-addr: 0.0.0.0:8889" >> /root/.config/code-server/config.yaml && \
	echo "auth: password" >> /root/.config/code-server/config.yaml && \
	echo "password: ${DEFAULT_PASSWD}" >> /root/.config/code-server/config.yaml && \
	echo "cert: false" >> /root/.config/code-server/config.yaml


RUN mkdir -p /home/${DEFAULT_USER}/r_packages
RUN mv /usr/local/lib/R/site-library /home/${DEFAULT_USER}/r_packages


RUN  echo . /opt/conda/etc/profile.d/conda.sh >>/home/${DEFAULT_USER}/.bashrc && \
	echo conda activate ${DEFAULT_USER} >> /home/${DEFAULT_USER}/.bashrc && \
	echo RETICULATE_PYTHON="/opt/conda/envs/${DEFAULT_USER}/bin/python" >> /home/${DEFAULT_USER}/.Renviron && \
	echo R_LIBS_USER="/home/cysics/r_packages/site-library" >> /home/${DEFAULT_USER}/.Renviron && \
	source /home/${DEFAULT_USER}/.bashrc


 #package install 
RUN apt-get install --reinstall build-essential -y && \
	apt-get install libxml2-dev   libcurl4-openssl-dev   gdal-bin proj-bin libgdal-dev libproj-dev   \
	default-jre default-jdk    libpcre2-dev libbz2-dev zlib1g-dev    libfontconfig1-dev \
	libharfbuzz-dev libfribidi-dev     zlib1g-dev -y 
RUN R CMD javareconf -n

RUN R -e "install.packages(c('languageserver', 'jsonlite', 'xml2', 'rvest', 'httr', 'haven', 'googlesheets4', 'googledrive', 'rgdal','rJava', 'devtools'), dependencies=TRUE,repos='http://cran.rstudio.com/')"
RUN TZ="Australia/Sydney" R -e 'install.packages("tidyverse")'

RUN conda activate ${DEFAULT_USER} && \
         conda install -c anaconda tensorflow-gpu=2.4.1 tensorflow-estimator=2.4.1  --quiet --yes && \
	conda install -c conda-forge tensorboard=2.4.1 keras=2.4.3 --quiet --yes && \
	conda install scipy==1.9.1 --yes 
	
RUN /opt/conda/envs/${DEFAULT_USER}/bin/pip install torch==1.12.0+cu113 torchvision==0.13.0+cu113 torchaudio==0.12.0 --extra-index-url https://download.pytorch.org/whl/cu113 

RUN  echo . /opt/conda/etc/profile.d/conda.sh >>/home/${DEFAULT_USER}/.bashrc && \
	echo conda activate DL >> /home/${DEFAULT_USER}/.bashrc && \
	echo export RETICULATE_PYTHON=/opt/conda/envs/${DEFAULT_USER}/bin/python >> /home/${DEFAULT_USER}/.bashrc && \
	echo export RETICULATE_PYTHON=/opt/conda/envs/${DEFAULT_USER}/bin/python >> /etc/profile && \
	echo export RETICULATE_PYTHON=/opt/conda/envs/${DEFAULT_USER}/bin/python >> /etc/security/pam_env.conf && \
	echo RETICULATE_PYTHON="/opt/conda/envs/${DEFAULT_USER}/bin/python" >> /home/${DEFAULT_USER}/.Renviron && \
	source /home/${DEFAULT_USER}/.bashrc





# CMD  [ "/bin/bash","-c", "/usr/lib/rstudio-server/bin/rserver --server-daemonize=0 & /opt/conda/envs/${DEFAULT_USER}/bin/jupyter notebook & /usr/bin/shiny-server & code-server"]
 CMD ["/bin/bash", "-c",   "/usr/lib/rstudio-server/bin/rserver --server-daemonize=0 & /usr/bin/shiny-server & code-server"]
