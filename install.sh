# !bin/bash

apt-get update

#apt-get upgrade

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 4B7C549A058F8B6B
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list

apt install mongodb-org

service mongod stop

# setup logs folders
mkdir -p /var/log/mongodb
rm -rf /var/log/mongodb.log
chown -R mongodb:mongodb /var/log/mongodb

# setup data folders
mkdir -p /var/lib/mongodb/server_01 /var/lib/mongodb/server_02
chown -R mongodb:mongodb /var/lib/mongodb
chmod 755 /var/lib/mongodb

# setup configs
mkdir -p /etc/mongodb

openssl rand -base64 741 >/etc/mongodb/key

mv /etc/mongod.conf /etc/mongodb/mongod.conf

sed -i -E 's/(systemLog:$)/\1\n  verbosity: 0/' /etc/mongodb/mongod.conf
sed -i -E 's/(systemLog:$)/\1\n  traceAllExceptions: false/' /etc/mongodb/mongod.conf

sed -i -E 's/(bindIp:).*$/\1 0.0.0.0/' /etc/mongodb/mongod.conf

sed -i -E 's/#(operationProfiling:)$/\1/' /etc/mongodb/mongod.conf
sed -i -E 's/(operationProfiling:$)/\1\n  slowOpThresholdMs: 2100/' /etc/mongodb/mongod.conf
sed -i -E 's/(operationProfiling:$)/\1\n  mode: off/' /etc/mongodb/mongod.conf

sed -i -E 's/#(replication:)$/\1/' /etc/mongodb/mongod.conf
sed -i -E 's/(replication:$)/\1\n  replSetName: rs0/' /etc/mongodb/mongod.conf

cp /etc/mongodb/mongod.conf /etc/mongodb/mongod_01.conf
cp /etc/mongodb/mongod.conf /etc/mongodb/mongod_02.conf

sed -i -E 's/(port:).*$/\1 27017/' /etc/mongodb/mongod_01.conf
sed -i -E 's/(dbPath:).*$/\1 \/var\/lib\/mongodb\/server_01/' /etc/mongodb/mongod_01.conf
sed -i -E 's/(path:).*$/\1 \/var\/log\/mongodb\/mongod_01.log/' /etc/mongodb/mongod_01.conf
sed -i -E 's/(processManagement:$)/\1\n  pidFilePath: \/var\/run\/mongodb\/mongod_01.pid/' /etc/mongodb/mongod_01.conf

sed -i -E 's/(port:).*$/\1 27018/' /etc/mongodb/mongod_02.conf
sed -i -E 's/(dbPath:).*$/\1 \/var\/lib\/mongodb\/server_02/' /etc/mongodb/mongod_02.conf
sed -i -E 's/(path:).*$/\1 \/var\/log\/mongodb\/mongod_02.log/' /etc/mongodb/mongod_02.conf
sed -i -E 's/(processManagement:$)/\1\n  pidFilePath: \/var\/run\/mongodb\/mongod_02.pid/' /etc/mongodb/mongod_02.conf

chown -R mongodb:mongodb /etc/mongodb
chmod 400 /etc/mongodb/key

# setup pid services folder
mkdir -p /var/run/mongodb/
chown -R mongodb:mongodb /var/run/mongodb/

# setup services
cp /lib/systemd/system/mongod.service /lib/systemd/system/mongod_01.service
cp /lib/systemd/system/mongod.service /lib/systemd/system/mongod_02.service

sed -i -E 's/(ExecStart=.*?--config).*$/\1 \/etc\/mongodb\/mongod_01.conf/' /lib/systemd/system/mongod_01.service
sed -i -E 's/(PIDFile=).*$/\1 \/var\/run\/mongodb\/mongod_01.pid/' /lib/systemd/system/mongod_01.service
sed -i -E 's/(LimitMEMLOCK=.*)$/\1\nRestart=always/' /lib/systemd/system/mongod_01.service

sed -i -E 's/(ExecStart=.*?--config).*$/\1 \/etc\/mongodb\/mongod_02.conf/' /lib/systemd/system/mongod_02.service
sed -i -E 's/(PIDFile=).*$/\1 \/var\/run\/mongodb\/mongod_02.pid/' /lib/systemd/system/mongod_02.service
sed -i -E 's/(LimitMEMLOCK=.*)$/\1\nRestart=always/' /lib/systemd/system/mongod_02.service

rm -rf /lib/systemd/system/mongod.service

sudo systemctl daemon-reload

service mongod_01 restart
service mongod_02 restart

# replica set
replica_host=$(cat .env | grep 'REPLICA_HOST=' | sed 's/REPLICA_HOST=//')
mongo <<<$(cat replica.conf | sed -e 's/{REPLICA_HOST}/'$replica_host'/' | sed -e 's/{REPLICA_HOST_2}/'$replica_host'/')

# root user set
root_password=$(cat .env | grep 'ROOT_PASSWORD=' | sed 's/ROOT_PASSWORD=//')
root_data=$(cat user.conf | sed -e 's/{ROOT_PASSWORD}/'$root_password'/')
mongo --port 27017 <<<$(echo $root_data)

# auth set
sed -i -E 's/(ExecStart=.*)$/\1 --auth/' /lib/systemd/system/mongod_01.service
sed -i -E 's/#(security:)$/\1/' /etc/mongodb/mongod_01.conf
sed -i -E 's/(security:$)/\1\n  keyFile: \/etc\/mongodb\/key/' /etc/mongodb/mongod_01.conf

sed -i -E 's/(ExecStart=.*)$/\1 --auth/' /lib/systemd/system/mongod_02.service
sed -i -E 's/#(security:)$/\1/' /etc/mongodb/mongod_02.conf
sed -i -E 's/(security:$)/\1\n  keyFile: \/etc\/mongodb\/key/' /etc/mongodb/mongod_02.conf

sudo systemctl daemon-reload

service mongod_01 restart
service mongod_02 restart

# app password set
app_password=$(cat .env | grep 'APP_PASSWORD=' | sed 's/APP_PASSWORD=//')
app_user=$(cat .env | grep 'APP_USER=' | sed 's/APP_USER=//')
app_db=$(cat .env | grep 'APP_DB=' | sed 's/APP_DB=//')
app_data=$(cat app.conf | sed -e 's/{APP_PASSWORD}/'$app_password'/' | sed -e 's/{APP_DB}/'$app_db'/' | sed -e 's/{APP_USER}/'$app_user'/')
mongo --port 27017 -u "mongo-root" -p "$root_password" --authenticationDatabase "admin" <<<$(echo $app_data)

# connection string
# mongodb://user:password@localhost:27017,localhost:27018/local?authSource=admin&replicaSet=rs0
