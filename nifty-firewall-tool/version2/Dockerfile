FROM ubuntu:latest

RUN apt update 
RUN DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles apt-get -y install tzdata
RUN apt install nftables iproute2 -y
RUN apt upgrade -y
RUN mkdir KeyboardKowboys
COPY . /KeyboardKowboys
WORKDIR /KeyboardKowboys
ENTRYPOINT [ "./nifty-firewall-tool" ]
