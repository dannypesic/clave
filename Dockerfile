  FROM alpine:latest                                                                                                                                                                                        
                  
  RUN apk add --no-cache \                                                                                                                                                                                  
      gcc make musl-dev flex bison perl bash cpio \
      xorriso dosfstools mtools bc linux-headers \                                                                                                                                                          
      elfutils-dev openssl-dev curl tar xz wget git wpa_supplicant
                                                                                                                                                                                                            
  RUN curl -L https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.22.tar.xz \
      -o /tmp/linux.tar.xz && \
      mkdir -p /kernel && \
      tar xf /tmp/linux.tar.xz -C /kernel && \
      rm /tmp/linux.tar.xz                                                                                                                                                                                  
   
  RUN mkdir -p /build

  WORKDIR /