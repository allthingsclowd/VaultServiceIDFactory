// VaultServiceIDFactory
// SIMPLE API SERVICE THAT UPON RECEIPT OF AN APPROLEID PROVIDES A SERVICEID
// FACILITATES BOOTSTRAPPING OF APPLICATIONS
package main

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

var (
	vcertFile = flag.String("vaultcert", "/etc/vault.d/pki/tls/certs/vault-client.pem", "A PEM eoncoded vault certificate file.")
	vkeyFile  = flag.String("vaultkey", "/etc/vault.d/pki/tls/private/vault-client-key.pem", "A PEM encoded vault private key file.")
	vcaFile   = flag.String("vaultCA", "/etc/ssl/certs/vault-agent-ca.pem", "A PEM eoncoded CA's vault certificate file.")
)

type vault struct {
	Token string
}

type approle struct {
	RoleName string
}

var appHealth = "UNINITIALISED"
var unwrappedToken = "UNINITIALISED"
var targetPort string
var targetIP string
var thisServer string
var vaultAddress string

// BOOTSTRAP THIS APPLICATION WITH A WRAPPED VAULT TOKEN
func initialiseme(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/initialiseme" {
		http.Error(w, "404 not found.", http.StatusNotFound)
		return
	}

	switch r.Method {
	case "POST":
		decoder := json.NewDecoder(r.Body)
		var apiKey vault
		err := decoder.Decode(&apiKey)
		if err != nil {
			fmt.Fprintf(w, "Invalid Data Received in Request Body.\n Format expected '{ \"token\" : \"123456\" }'\nError : %v \n", err)
			return
		}

		unwrappedTokenResponse, success := queryVault(vaultAddress, "/v1/sys/wrapping/unwrap", apiKey.Token, nil, "POST", false)
		if !success {
			appHealth = "UNWRAPTOKENFAIL"
			fmt.Fprintf(w, "Vault token unwrap failure\n")
			return
		}

		unwrappedToken = unwrappedTokenResponse["auth"].(map[string]interface{})["client_token"].(string)
		log.Println(unwrappedToken)
		fmt.Fprintf(w, "Wrapped Token Received: %v \n", apiKey.Token)
		fmt.Fprintf(w, "UnWrapped Vault Provisioner Role Token Received: %v \n", unwrappedToken)
		appHealth = "INITIALISED"
	default:
		fmt.Fprintf(w, "Sorry, only POST methods are supported.\n")
	}
	return
}

// UPON RECEIPT OF A VALID APPROLENAME IN A JSON POST RETURN A WRAPPED SECRETID
func approlename(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/approlename" {
		http.Error(w, "404 not found.", http.StatusNotFound)
		return
	}

	switch r.Method {
	case "POST":
		if appHealth == "INITIALISED" || appHealth == "TOKENDELIVERED" {
			decoder := json.NewDecoder(r.Body)
			var role approle
			err := decoder.Decode(&role)
			if err != nil {
				fmt.Fprintf(w, "Invalid Data Received in Request Body.\n Format expected '{ \"roleName\" : \"VaultSecretIDFactory\" }'\nError : %v \n", err)
				return
			}
			secretidURL := "/v1/auth/approle/role/" + role.RoleName + "/secret-id"
			wrappedSecretResponse, success := queryVault(vaultAddress, secretidURL, unwrappedToken, nil, "POST", true)
			if !success {
				appHealth = "WRAPSECRETIDFAIL"
				fmt.Fprintf(w, "Retreval of Secret ID failure\n")
				return
			}
			wrappedSecretID := wrappedSecretResponse["wrap_info"].(map[string]interface{})["token"].(string)
			log.Println(wrappedSecretID)
			fmt.Fprintf(w, wrappedSecretID)
			appHealth = "TOKENDELIVERED"
		} else {
			fmt.Fprintf(w, "Please get a Vault Factory Service Administrator to initialise this Service.")
		}
		return
	default:
		fmt.Fprintf(w, "Sorry, only POST methods are supported.")
		return
	}
}

func health(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/health" {
		http.Error(w, "404 not found.", http.StatusNotFound)
		return
	}

	switch r.Method {
	case "GET":
		log.Println(appHealth)
		fmt.Fprintf(w, appHealth)
		return
	default:
		fmt.Fprintf(w, "Sorry, only GET methods are supported.")
		return
	}
}

func main() {

	portPtr := flag.Int("port", 8314, "Default's to port 8314. Use -port=nnnn to use listen on an alternate port.")
	ipPtr := flag.String("ip", "127.0.0.1", "Default's to all interfaces by using 127.0.0.1")
	vaultAddressPtr := flag.String("vault", "https://localhost:8322", "Vault IP Address - defaults to localhost")

	flag.Parse()
	vaultAddress = *vaultAddressPtr

	targetPort = strconv.Itoa(*portPtr)
	targetIP = *ipPtr
	thisServer, _ = os.Hostname()
	fmt.Printf("Incoming port number: %s \n", targetPort)
	fmt.Printf("Incoming vault address: %s \n", vaultAddress)

	var portDetail strings.Builder
	portDetail.WriteString(targetIP)
	portDetail.WriteString(":")
	portDetail.WriteString(targetPort)
	fmt.Printf("URL: %s \n", portDetail.String())

	http.HandleFunc("/health", health)
	http.HandleFunc("/initialiseme", initialiseme)
	http.HandleFunc("/approlename", approlename)
	log.Fatal(http.ListenAndServe(portDetail.String(), nil))
}

func queryVault(vaultAddress string, url string, token string, data map[string]interface{}, action string, wrapped bool) (map[string]interface{}, bool) {

	var success = true
	var result map[string]interface{}

	// Load client cert
	cert, err := tls.LoadX509KeyPair(*vcertFile, *vkeyFile)
	if err != nil {
		log.Fatal(err)
	}

	// Load CA cert
	caCert, err := ioutil.ReadFile(*vcaFile)
	if err != nil {
		log.Fatal(err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	// Setup HTTPS client
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      caCertPool,
		//    InsecureSkipVerify: true,
	}
	tlsConfig.BuildNameToCertificate()
	transport := &http.Transport{TLSClientConfig: tlsConfig}
	client := &http.Client{Transport: transport}

	fmt.Println("\nDebug Vars Start")
	fmt.Println("\nVAULT_ADDR:>", vaultAddress)
	fmt.Println("\nURL:>", url)
	fmt.Println("\nTOKEN:>", token)
	fmt.Println("\nDATA:>", data)
	fmt.Println("\nVERB:>", action)
	fmt.Println("\nDebug Vars End")

	apiCall := vaultAddress + url
	bytesRepresentation, err := json.Marshal(data)
	if err != nil {
		fmt.Println("Failed to query the Vault API \nError : ", err)
		success = false
		return result, success
	}

	req, err := http.NewRequest(action, apiCall, bytes.NewBuffer(bytesRepresentation))
	if err != nil {
		fmt.Println("Failed to query the Vault API \nError : ", err)
		success = false
		return result, success
	}
	req.Header.Set("X-Vault-Token", token)
	req.Header.Set("Content-Type", "application/json")
	if wrapped {
		req.Header.Set("X-Vault-Wrap-TTL", "5m")
	}

	//client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Println("Failed to query the Vault API \nError : ", err)
		success = false
		return result, success
	}
	defer resp.Body.Close()

	fmt.Println("response Status:", resp.Status)
	fmt.Println("response Headers:", resp.Header)

	json.NewDecoder(resp.Body).Decode(&result)

	fmt.Println("\n\nresponse result: ", result)
	// fmt.Println("\n\nresponse result .auth:",result["auth"].(map[string]interface{})["client_token"])

	return result, success
}
