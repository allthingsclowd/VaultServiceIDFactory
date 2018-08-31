// VaultServiceIDFactory
// SIMPLE API SERVICE THAT UPON RECEIPT OF AN APPROLEID PROVIDES A SERVICEID
// FACILITATES BOOTSTRAPPING OF APPLICATIONS
package main

import (
    "flag"
    "encoding/json"
    "log"
	"net/http"
    "fmt"
    "strconv"
    "os"
    "strings"
    "bytes"
)

type vault struct {
    Token string
}

type approle struct {
    Name string
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
        }
        wrappedToken, success := queryVault(vaultAddress, "/v1/sys/wrapping/unwrap", apiKey.Token, nil, "POST", false)
        if !success {
            appHealth = "UNWRAPTOKENFAIL"
            fmt.Fprintf(w, "Vault token unwrap failure\n")
            return
        }
	    unwrappedToken = wrappedToken["data"].(map[string]interface{})["secret_id"].(string)
		log.Println(unwrappedToken)
        fmt.Fprintf(w, "Token Received: %v", apiKey.Token)
        appHealth = "INITIALISED"
    default:
        fmt.Fprintf(w, "Sorry, only POST methods are supported.")
    }
}

// UPON RECEIPT OF A VALID APPROLENAME IN A JSON POST RETURN A WRAPPED SECRETID
func approlename(w http.ResponseWriter, r *http.Request) {
    if r.URL.Path != "/approlename" {
        http.Error(w, "404 not found.", http.StatusNotFound)
        return
    }
 
    switch r.Method {
    case "POST":
        if appHealth == "INITIALISED" ******* or "TOKENDELIVERED" ******** {
            decoder := json.NewDecoder(r.Body)
            var role approle
            err := decoder.Decode(&role)
            if err != nil {
                fmt.Fprintf(w, "Invalid Data Received in Request Body.\n Format expected '{ \"roleid\" : \"123456\" }'\nError : %v \n", err)
            }
            secretidURL := "/v1/auth/approle/role/" + role.Name + "/secret-id"
            wrappedSecretResponse, success := queryVault(vaultAddress, secretidURL, unwrappedToken, nil, "POST", true)
            if !success {
                appHealth = "WRAPSECRETIDFAIL"
                fmt.Fprintf(w, "Retreval of Secret ID failure\n")
                return
            }
            wrappedSecretID := wrappedSecretResponse["wrap_info"].(map[string]interface{})["token"].(string)
            log.Println(wrappedSecretID)
            fmt.Fprintf(w, "Token Received: %v", wrappedSecretID)
            appHealth = "TOKENDELIVERED"
        } else {
            fmt.Fprintf(w, "Please get a Vault Factory Service Administrator to initialise this Service.")
        }
    default:
        fmt.Fprintf(w, "Sorry, only POST methods are supported.")
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
    default:
        fmt.Fprintf(w, "Sorry, only GET methods are supported.")
    }
}

func main() {

    portPtr := flag.Int("port", 8314, "Default's to port 8314. Use -port=nnnn to use listen on an alternate port.")
    ipPtr := flag.String("ip", "0.0.0.0", "Default's to all interfaces by using 0.0.0.0")
    vaultAddressPtr := flag.String("vault", "http://192.168.2.11:8200", "Vault IP Address - defaults to 192.168.2.11")
    vaultAddress = *vaultAddressPtr
    flag.Parse()
    
	targetPort = strconv.Itoa(*portPtr)
	targetIP = *ipPtr
	thisServer, _ = os.Hostname()
    fmt.Printf("Incoming port number: %s \n", targetPort)

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
    
    fmt.Println("\nDebug Vars Start")
	fmt.Println("\nVAULT_ADDR:>", vaultAddress)
	fmt.Println("\nURL:>", url)
	fmt.Println("\nTOKEN:>", token)
	fmt.Println("\nDATA:>", data)
	fmt.Println("\nVERB:>", action)
	fmt.Println("\nDebug Vars End")

	apiCall := vaultAddress + url
	bytesRepresentation, err := json.Marshal(data)

    req, err := http.NewRequest(action, apiCall, bytes.NewBuffer(bytesRepresentation))
    req.Header.Set("X-Vault-Token", token)
    req.Header.Set("Content-Type", "application/json")
    if wrapped {
        req.Header.Set("X-Vault-Wrap-TTL","5m")
    }

    client := &http.Client{}
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

	fmt.Println("\n\nresponse result: ",result)
	fmt.Println("\n\nresponse result .auth:",result["auth"].(map[string]interface{})["client_token"])

	return result, success
}
