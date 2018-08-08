package main

import (
    "encoding/json"
    "log"
	"net/http"
	"fmt"
)

type vault struct {
    Token string
}

type approle struct {
    Id string
}

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
			panic(err)
		}
		log.Println(apiKey.Token)
		fmt.Fprintf(w, "Token Received: %v", apiKey.Token)
    default:
        fmt.Fprintf(w, "Sorry, only POST methods are supported.")
    }
}

func approleid(w http.ResponseWriter, r *http.Request) {
    if r.URL.Path != "/approleid" {
        http.Error(w, "404 not found.", http.StatusNotFound)
        return
    }
 
    switch r.Method {
    case "POST":
		decoder := json.NewDecoder(r.Body)
		var role approle
		err := decoder.Decode(&role)
		if err != nil {
			panic(err)
		}
		log.Println(role.Id)
		fmt.Fprintf(w, "AppRoleID Received: %v", role.Id)
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
		log.Println("Aplication HEALTH")
		fmt.Fprintf(w, "Aplication HEALTH")
    default:
        fmt.Fprintf(w, "Sorry, only GET methods are supported.")
    }
}

func main() {
	http.HandleFunc("/health", health)
	http.HandleFunc("/initialiseme", initialiseme)
	http.HandleFunc("/approleid", approleid)
    log.Fatal(http.ListenAndServe(":8314", nil))
}