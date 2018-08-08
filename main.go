package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"bytes"

	"github.com/gorilla/mux"
	consul "github.com/hashicorp/consul/api"
	vault "github.com/hashicorp/vault/api"
)

var apphealth = "UNINITIALISED"
var consulClient *consul.Client
var targetPort string
var targetIP string
var thisServer string
var portDetail strings.Builder

func main() {
	// set the port that the goapp will listen on - defaults to 8080

	portPtr := flag.Int("port", 8314, "Default's to port 8080. Use -port=nnnn to use listen on an alternate port.")
	ipPtr := flag.String("ip", "0.0.0.0", "Default's to all interfaces by using 0.0.0.0")
	//templatePtr := flag.String("templates", "templates/*.html", "Default's to templates/*.html -templates=????")
	flag.Parse()
	targetPort = strconv.Itoa(*portPtr)
	targetIP = *ipPtr
	thisServer, _ = os.Hostname()
	fmt.Printf("Incoming port number: %s \n", targetPort)
	// initialisation section
	

	// running section
	portDetail.WriteString(targetIP)
	portDetail.WriteString(":")
	portDetail.WriteString(targetPort)
	fmt.Printf("URL: %s \n", portDetail.String())

	handleRequests()

}

func setHeaders(w http.ResponseWriter) http.ResponseWriter {
	w.Header().Set("SecretIDFactoryIP", targetIP)
	w.Header().Set("SecretIDFactoryServer", thisServer)
	w.Header().Set("SecretIDFactoryPort", targetPort)
	return w
}

func bootstrapHandler(w http.ResponseWriter, r *http.Request) {

	w = setHeaders(w)

	_, apiErr := w.Write([]byte("Post an initialisation token to this endpoint\n"))
	if apiErr != nil {
		fmt.Printf("Failed to Load Application Status Page: %v \n", apiErr)
		apphealth = "UNINITIALISED POST FAILURE"
	}
}

func bootstrapHandlerRedirect(w http.ResponseWriter, r *http.Request) {

	w = setHeaders(w)

	_, apiErr := w.Write([]byte("Post an initialisation token to this endpoint\n"))
	if apiErr != nil {
		fmt.Printf("Failed to Load Application Status Page: %v \n", apiErr)
		apphealth = "UNINITIALISED POST FAILURE"
	}
}

func approleidHandlerRedirect(w http.ResponseWriter, r *http.Request) {

	w = setHeaders(w)

	_, apiErr := w.Write([]byte("Post an initialisation token to this endpoint\n"))
	if apiErr != nil {
		fmt.Printf("Failed to Load Application Status Page: %v \n", apiErr)
		apphealth = "UNINITIALISED POST FAILURE"
	}
}

func approleidHandler(w http.ResponseWriter, r *http.Request) {

	w = setHeaders(w)

	_, apiErr := w.Write([]byte("Post an approle-id to this endpoint\n"))
	if apiErr != nil {
		fmt.Printf("Failed to Load Application Status Page: %v \n", apiErr)
		apphealth = "UNINITIALISED POST FAILURE"
	}
}

func handleRequests() {
	
	r := mux.NewRouter()
	r.HandleFunc("/initialiseme", bootstrapHandlerRedirect).Methods("GET")
	r.HandleFunc("/initialiseme", bootstrapHandler).Methods("POST")
	r.HandleFunc("/approleid", approleidHandlerRedirect).Methods("GET")
	r.HandleFunc("/approleid", approleidHandler).Methods("POST")
	r.HandleFunc("/health", healthHandler).Methods("GET")

	http.Handle("/initialiseme", r)
	http.ListenAndServe(portDetail.String(), r)

}

func healthHandler(w http.ResponseWriter, r *http.Request) {

	w = setHeaders(w)

	fmt.Printf("Application Status: %v \n", apphealth)

	_, apiErr := w.Write([]byte("Application Status: " + apphealth))
	if apiErr != nil {
		fmt.Printf("Failed to Load Application Status Page: %v \n", apiErr)
		apphealth = "HEALTH API FAILURE"
	}

}

func getVaultKV(vaultKey string) string {

	// Get the static approle id - this could be baked into a base image
	appRoleIDFile, err := ioutil.ReadFile("/usr/local/bootstrap/.approle-id")
	if err != nil {
		fmt.Print(err)
	}
	appRoleID := string(appRoleIDFile)
	fmt.Printf("App-Role ID Returned : >> %v \n", appRoleID)

	// Get a provisioner token to generate a new secret -id ... this would usually occur in the orchestrator rather than the app???
	vaultTokenFile, err := ioutil.ReadFile("/usr/local/bootstrap/.provisioner-token")
	if err != nil {
		fmt.Print(err)
	}
	vaultToken := string(vaultTokenFile)
	fmt.Printf("Secret Token Returned : >> %v \n", vaultToken)

	// Read in the Vault address from consul
	// vaultIP := getConsulKV(*consulClient, "LEADER_IP")
	vaultAddress := "http://" + "123.123.123.123" + ":8200"
	fmt.Printf("Secret Store Address : >> %v \n", vaultAddress)

	// Get a handle to the Vault Secret KV API
	vaultClient, err := vault.NewClient(&vault.Config{
		Address: vaultAddress,
	})
	if err != nil {
		fmt.Printf("Failed to get VAULT client >> %v \n", err)
		return "FAIL"
	}
	
	vaultClient.SetToken(vaultToken)
	
	// Generate a new Vault Secret-ID
    resp, err := vaultClient.Logical().Write("/auth/approle/role/goapp/secret-id", nil)
    if err != nil {
		fmt.Printf("Failed to get Secret ID >> %v \n", err)
		return "Failed"
    }
    if resp == nil {
		fmt.Printf("Failed to get Secfret ID >> %v \n", err)
		return "Failed"
    }

	secretID := resp.Data["secret_id"].(string)
	fmt.Printf("Secret ID Request Response : >> %v \n", secretID)

	// Now using both the APP Role ID & the Secret ID generated above
	data := map[string]interface{}{
        "role_id":   appRoleID,
		"secret_id": secretID,
	}

	fmt.Printf("Secret ID in map : >> %v \n", data)
	
	// Use the AppRole Login api call to get the application's Vault Token which will grant it access to the REDIS database credentials
	appRoletokenResponse := queryVault(vaultAddress,"/v1/auth/approle/login","",data,"POST")

	appRoletoken := appRoletokenResponse["auth"].(map[string]interface{})["client_token"]

	fmt.Printf("New API Secret Token Request Response : >> %v \n", appRoletoken)

	vaultClient.SetToken(appRoletoken.(string))

	completeKeyPath := "kv/development/" + vaultKey
	fmt.Printf("Secret Key Path : >> %v \n", completeKeyPath)

	// Read the Redis Credientials from VAULT
	vaultSecret, err := vaultClient.Logical().Read(completeKeyPath)
	if err != nil {
		fmt.Printf("Failed to read VAULT key value %v - Please ensure the secret value exists in VAULT : e.g. vault kv get %v >> %v \n", vaultKey, completeKeyPath, err)
		return "FAIL"
	}
	fmt.Printf("Secret Returned : >> %v \n", vaultSecret.Data["value"])
	result := vaultSecret.Data["value"]
	fmt.Printf("Secret Result Returned : >> %v \n", result.(string))
	return result.(string)
}

func queryVault(vaultAddress string, url string, token string, data map[string]interface{}, action string) map[string]interface{} {
	fmt.Println("\nDebug Vars Start")
	fmt.Println("\nVAULT_ADDR:>", vaultAddress)
	fmt.Println("\nURL:>", url)
	fmt.Println("\nTOKEN:>", token)
	fmt.Println("\nDATA:>", data)
	fmt.Println("\nVERB:>", action)
	fmt.Println("\nDebug Vars End")

	apiCall := vaultAddress + url
	bytesRepresentation, err := json.Marshal(data)

	//var jsonStr = []byte(`{"title":"Buy cheese and bread for breakfast."}`)
    req, err := http.NewRequest(action, apiCall, bytes.NewBuffer(bytesRepresentation))
    req.Header.Set("X-Vault-Token", token)
    req.Header.Set("Content-Type", "application/json")

    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        panic(err)
    }
    defer resp.Body.Close()

    fmt.Println("response Status:", resp.Status)
	fmt.Println("response Headers:", resp.Header)
	
	var result map[string]interface{}

	json.NewDecoder(resp.Body).Decode(&result)

	fmt.Println("\n\nresponse result: ",result)
	fmt.Println("\n\nresponse result .auth:",result["auth"].(map[string]interface{})["client_token"])

	return result
}
