#! /usr/bin/env bash

PASSWORD="password"
DOMAIN_NAME="localhost.dev"
BROKERS=(kafkabroker)
COMPONENTS=(ksql controlcenter producer consumer)
rm -rf certs || true

mkdir certs
cd certs
mkdir ca ${BROKERS[@]} ${COMPONENTS[@]}
cd ..

# create new CA, out: a ca key (private key of the ca) 
# and a ca certificate (public one, to be imported to truststore, can be distributed to anyone needs to trust the ca generated)
openssl req -new -newkey rsa:2048 -days 365 -x509 -sha256 -subj "/CN=Kafka-Security-CA" -keyout "certs/ca/ca-key" -out "certs/ca/ca-cert" -nodes


for component in ${BROKERS[@]}; do
    cat > "certs/${component}/openssl.cnf" << EOF
[req]
[req]
default_bits = 2048
encrypt_key  = no # Change to encrypt the private key using des3 or similar
default_md   = sha256
prompt       = no
utf8         = yes
# Extensions for SAN IP and SAN DNS
req_extensions = v3_req
# Allow client and server auth. You may want to only allow server auth.
# Link to SAN names.
[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names
# Alternative names are specified as IP.# and DNS.# for IP addresses and
# DNS accordingly. 
[alt_names]
DNS.1 = ${component}.${DOMAIN_NAME}
EOF
    # create broker keystore within the broker certificate.
    # out: keystore.jks file
    # check: keytool -list -v -keystore <keystore_file>
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -validity 3650 -genkey -keyalg rsa -sigalg SHA256withRSA -keysize 2048 -storepass $PASSWORD -keypass $PASSWORD -dname "CN=${component}.${DOMAIN_NAME}" -ext SAN=DNS:"${component}.${DOMAIN_NAME}"
    
    # export priv key from keystore
    keytool -importkeystore -srckeystore "certs/${component}/${component}.keystore.jks" -srcstorepass $PASSWORD -srckeypass $PASSWORD -srcalias localhost -destalias localhost -destkeystore "certs/${component}/${component}.keystore.p12" -deststoretype PKCS12 -deststorepass $PASSWORD -destkeypass $PASSWORD
    openssl pkcs12 -in "certs/${component}/${component}.keystore.p12" -nodes -nocerts -out "certs/${component}/${component}.priv_key.pem" -passin pass:$PASSWORD -passout pass:$PASSWORD

    # create the request certificate to be signed
    # out: it is file "csr".
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -certreq -file "certs/${component}/csr" -storepass $PASSWORD

    # sign the certificate of the broker, so all the clients are able to verify if the certificate of the broker is valid. 
    # out: file "crt" (certificate request trusted), certificate signed by the ca.
    # check: keytool -printcert -v -file <ca_cert_file>
    openssl x509 -sha256 -req -CA "certs/ca/ca-cert" -CAkey "certs/ca/ca-key" -CAcreateserial -in "certs/${component}/csr" -out "certs/${component}/crt" -days 3650 -passin pass:$PASSWORD  -extensions v3_req -extfile "certs/${component}/openssl.cnf"
    
    # create truststore in broker. Adding alias CA-root to the certificate, importing the public ca-cert of the CA.
    keytool -keystore "certs/${component}/${component}.truststore.jks" -alias CARoot -import -file "certs/ca/ca-cert" -storepass $PASSWORD -noprompt -v
    
    # import new certificates in broker keystore.
    # import public ca-cert in keystore.
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias CARoot -import -file "certs/ca/ca-cert" -storepass $PASSWORD -noprompt -v
    
    # import signed certificate of the broker in keystore.
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -import -file "certs/${component}/crt" -storepass $PASSWORD -v


    echo "${PASSWORD}" > "certs/${component}/password"
done

for component in ${COMPONENTS[@]}; do
    cat > "certs/${component}/openssl.cnf" << EOF
[req]
[req]
default_bits = 2048
encrypt_key  = no # Change to encrypt the private key using des3 or similar
default_md   = sha256
prompt       = no
utf8         = yes
# Extensions for SAN IP and SAN DNS
req_extensions = v3_req
# Allow client and server auth. You may want to only allow server auth.
# Link to SAN names.
[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names
# Alternative names are specified as IP.# and DNS.# for IP addresses and
# DNS accordingly. 
[alt_names]
DNS.1 = ${component}.${DOMAIN_NAME}
EOF
    # create broker keystore within the broker certificate.
    # out: keystore.jks file
    # check: keytool -list -v -keystore <keystore_file>
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -validity 3650 -genkey -keyalg RSA -sigalg SHA256withRSA -keysize 2048 -storepass $PASSWORD -keypass $PASSWORD -dname "CN=${component}" -ext SAN=DNS:"${component}.${DOMAIN_NAME}"

    # export priv key from keystore
    keytool -importkeystore -srckeystore "certs/${component}/${component}.keystore.jks" -srcstorepass $PASSWORD -srckeypass $PASSWORD -srcalias localhost -destalias localhost -destkeystore "certs/${component}/${component}.keystore.p12" -deststoretype PKCS12 -deststorepass $PASSWORD -destkeypass $PASSWORD
    openssl pkcs12 -in "certs/${component}/${component}.keystore.p12" -nodes -nocerts -out "certs/${component}/${component}.priv_key.pem" -passin pass:$PASSWORD -passout pass:$PASSWORD

    # create the request certificate to be signed
    # out: it is file "csr".
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -sigalg SHA256withRSA -certreq -file "certs/${component}/csr" -storepass $PASSWORD
    
    # sign the certificate of the broker, so all the clients are able to verify if the certificate of the broker is valid. 
    # out: file "crt" (certificate request trusted), certificate signed by the ca.
    # check: keytool -printcert -v -file <ca_cert_file>
    openssl x509 -sha256 -req -CA "certs/ca/ca-cert" -CAkey "certs/ca/ca-key" -CAcreateserial -in "certs/${component}/csr" -out "certs/${component}/crt" -days 3650 -passin pass:$PASSWORD  -extensions v3_req -extfile "certs/${component}/openssl.cnf"
    
    # create truststore in broker. Adding alias CA-root to the certificate, importing the public ca-cert of the CA.
    keytool -keystore "certs/${component}/${component}.truststore.jks" -alias CARoot -import -file "certs/ca/ca-cert" -storepass $PASSWORD -noprompt -v
    
    # import new certificates in broker keystore.
    # import public ca-cert in keystore.
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias CARoot -import -file "certs/ca/ca-cert" -storepass $PASSWORD -noprompt -v
    
     # import signed certificate  of the broker in keystore.
    keytool -keystore "certs/${component}/${component}.keystore.jks" -alias localhost -import -file "certs/${component}/crt" -storepass $PASSWORD -v


    echo "${PASSWORD}" > "certs/${component}/password"
done
