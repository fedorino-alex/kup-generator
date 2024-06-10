FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -q update && apt-get -qy dist-upgrade
RUN apt-get -qy install \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-latex-recommended-doc- \
    texlive-latex-extra-doc- \
    texlive-fonts-recommended-doc- \
    texlive-latex-base-doc- \
    texlive-pictures-doc- \
    texlive-pstricks-doc-
RUN apt-get -q clean

RUN apt-get install -qy apt-transport-https ca-certificates curl gnupg lsb-release
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN az extension add --name azure-devops
RUN az devops configure --defaults organization=https://dev.azure.com/pdd-ihsmarkit/

RUN apt-get install -y jq
RUN apt-get install -y bc

WORKDIR /kup

COPY ./kup_report_template.tex .
COPY ./accuris-logo.png .
COPY ./report.sh .

ENTRYPOINT [ "./report.sh" ]

