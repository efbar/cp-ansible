#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SERVICE_INPUT=$1
SERVICE=${SERVICE_INPUT//_/}

echo "------------------------------- $SERVICE -------------------------------"

# create truststore in service. Adding alias CA-root to the certificate, importing the public ca-cert of the CA.
keytool -keystore "$DIR/$SERVICE.truststore.jks" -alias CARoot -import -file "$DIR/ca-cert" -storepass $2 -noprompt -v

# import new certificates in service keystore.
# import public ca-cert in keystore.
keytool -keystore "$DIR/$SERVICE.keystore.jks" -alias CARoot -import -file "$DIR/ca-cert" -storepass $2 -noprompt -v

# import signed certificate of the service in keystore.
keytool -keystore "$DIR/$SERVICE.keystore.jks" -alias localhost -import -file "$DIR/crt" -storepass $2 -noprompt -v

# import private key in service keystore
keytool -import -alias localhost -file "$SERVICE.priv_key.pem" -keystore "$DIR/$SERVICE.keystore.jks"