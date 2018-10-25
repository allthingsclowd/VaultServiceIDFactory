![https://travis-ci.org/allthingsclowd/VaultServiceIDFactory.svg?branch=master](https://travis-ci.org/allthingsclowd/VaultServiceIDFactory.svg?branch=master)

# Vault Service ID Factory

## A Service (Secret-ID Factory) that generates a wrapped secret-id upon receipt of an app-role - (api only)

This will be used as the broker between vault and applications to bootstrap the secret-id delivery process.

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
## Application Bootstrapping AppRole Workflow

How does the application get it's Vault token?
![image](https://user-images.githubusercontent.com/9472095/47363260-3bd19c80-d6ce-11e8-9720-72c8e400405d.png)


## Consul Connect Addition

![image](https://user-images.githubusercontent.com/9472095/47509126-52622a00-d86d-11e8-95f7-9da89fd2500c.png)

## TODO

### New Features


### Refactor
- create consul connect tests


## Done
__Secret-ID Factory__
- Build a new service (Secret-ID Factory) that generates a wrapped secret-id upon receipt of an app-role - (api only)
- Build this in a separate repository using a similar CI/CD pipeline mentality
- Added Consul Connect to the Service
