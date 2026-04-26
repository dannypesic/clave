docker build --platform linux/amd64 -t alpine:latest .                                                                                                                                                       
docker run --rm --platform linux/amd64 -it -v "$(pwd):/clave" alpine:latest
echo "Run ./setup.sh to initialize project setup"