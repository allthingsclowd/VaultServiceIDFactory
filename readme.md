![https://travis-ci.org/allthingsclowd/VaultServiceIDFactory.svg?branch=master](https://travis-ci.org/allthingsclowd/VaultServiceIDFactory.svg?branch=master)

# Vault Service ID Factory

## Solving Secret Zero or Application Boot strapping

![913ee4e2-b01c-4749-8daa-f3ec5f8e5203](https://user-images.githubusercontent.com/9472095/43364036-20dbed52-930a-11e8-9e93-6de1290108b6.png)

## An example service that generates a wrapped secret-id upon receipt of an approle name

This service will be used as the broker between vault and applications to bootstrap the secret-id delivery process.

The service defaults to port 8314.

It has the following 3 API endpoints - 
 
 1. /initialiseme - this endpoint requires a POST with the following json package { "token" : "wrapped token" }
 This should be a wrapped vault authentication token that has permission to create SECRET_IDs
 ``` bash
 curl --header 'Content-Type: application/json' --request POST --data '{"token":"b76e6d87-1719-2fe5-42a1-b2a528bfd817"}' http://localhost:8314/initialiseme
 ```
 Once a valid token is received the health status of the application is changed from `UNINITIALISED` to `INITIALISED`

 2. /approlename - this endpoint requires a POST with the following json package { "RoleName" : "id-factory" }
 ``` bash
 curl --header 'Content-Type: application/json' --request POST --data '{"RoleName":"id-factory"}' http://localhost:8314/approlename
 ```
 This endpoint only becomes operational once the application has been initialised through the endpoint outlined in 1 above.
 When a valid AppRole name is provided a matching WRAPPED Vault SECRET_ID Token is returned.

 3. /health - displays the current application state
 ``` bash
 curl http://localhost:8314/health
 ```

 ## Status
 ``` bash
 UNINITIALISED - no valid ##WRAPPED## vault token received
 INITIALISED - valid ##WRAPPED## vault token recieved
 TOKENDELIVERED - a wrapped secret-id has been returned to an api request
 WRAPSECRETIDFAIL - failed to generate a wrapped secret-id
```
# Vault's AppRole

## How to Bootstrap the Bootstrapping Service

A special token with limited scope, a provisioner token, is generated by a vault administrator and shared with the owner of the provisioner bootstrapping service. This token is used to initialise the Secret-ID Factory Service.

![image](https://user-images.githubusercontent.com/9472095/47529556-14322e00-d8a0-11e8-8c22-4a4f5b2fdbc3.png)

## Application Bootstrapping Workflow

How does the application get it's Vault token?

![image](https://user-images.githubusercontent.com/9472095/47529600-27dd9480-d8a0-11e8-83ba-bf9b507632cf.png)

## Consul Connect Addition

![image](https://user-images.githubusercontent.com/9472095/47515764-9bb97600-d87b-11e8-90a4-990ca1a19bce.png)


## Docker Image OverReview

__Building a new Image__
- Ensure to include all dependencies when compiling the go binary
``` golang
go get -t ./...
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o VaultServiceIDFactory main.go
```

- Build a new image (using Alpine imahe instead of scratch as need some additional commands)
``` bash
docker build -t vaultsecretidfactory -f dockerfile .
```

- Upload to docker registry
```bash
docker login [enter valid credentials]
docker tag vaultsecretidfactory allthingscloud/vaultsecretidfactory
docker push allthingscloud/vaultsecretidfactory
```

__Run the application__

- This container expects that the accompanying Vault service is running and the bootstrapping tokens have been created in the mounted directory
``` bash
vagrant up leader01
docker run -v $PWD:/usr/local/bootstrap/ allthingscloud/vaultsecretidfactory &
```

- If all went according to plan you should see the following output
``` bash
Grahams-MacBook-Pro:VaultServiceIDFactory grazzer$ docker run -v $PWD:/usr/local/bootstrap/ allthingscloud/vaultsecretidfactory &
[1] 58723
Grahams-MacBook-Pro:VaultServiceIDFactory grazzer$ Incoming port number: 8314
Incoming vault address: http://192.168.2.11:8200
URL: 0.0.0.0:8314
Running Docker locally with access to vagrant instance filesystem
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   845  100   338  100   507  12518  18777 --:--:-- --:--:-- --:--:-- 31296

Debug Vars Start

VAULT_ADDR:> http://192.168.2.11:8200

URL:> /v1/sys/wrapping/unwrap

TOKEN:> s.3VROD6THgIddAYWKt3sX2Ei1

DATA:> map[]

VERB:> POST

Debug Vars End
response Status: 200 OK
response Headers: map[Cache-Control:[no-store] Content-Type:[application/json] Date:[Tue, 06 Nov 2018 15:19:15 GMT] Content-Length:[413]]


response result:  map[renewable:false lease_duration:0 data:<nil> wrap_info:<nil> warnings:<nil> auth:map[policies:[default provisioner] token_policies:[default provisioner] metadata:<nil> entity_id: client_token:s.5BcLKYnzQWQR0pO9ikxTcrJ3 accessor:4RLti001aNJssblF2LFb3899 lease_duration:3600 renewable:true token_type:service] request_id:16bb23fa-c1b8-e954-113c-f7914bb0b002 lease_id:]
2018/11/06 15:19:42 s.5BcLKYnzQWQR0pO9ikxTcrJ3
Wrapped Token Received: s.3VROD6THgIddAYWKt3sX2Ei1
UnWrapped Vault Provisioner Role Token Received: s.5BcLKYnzQWQR0pO9ikxTcrJ3
2018/11/06 15:19:42 INITIALISED
INITIALISED
```


## TODO

### New Features


### Refactor



## Done
__Secret-ID Factory__
- Build a new service (Secret-ID Factory) that generates a wrapped secret-id upon receipt of an app-role - (api only)
- Build this in a separate repository using a similar CI/CD pipeline mentality
- Added Consul Connect to the Service
- create consul connect tests
