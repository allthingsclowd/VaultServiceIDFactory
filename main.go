package main

import (
	"log"
	"net/http"
	"github.com/gorilla/mux"
	"html/template"
	"github.com/go-redis/redis"
	"os"
	"strings"
	"github.com/hashicorp/consul/api"
	"strconv"
)

var templates *template.Template
var redisClient *redis.Client
var redisMaster string
var redisPassword string
var goapphealth = "GOOD"
var consulClient *api.Client

func main() {
	redisMaster, redisPassword = redisInit()

	if (redisMaster == "0") || (redisPassword == "0") {

		log.Printf("Check the Consul service is running")
		goapphealth = "NOTGOOD"

	} else {

		redisClient = redis.NewClient(&redis.Options{
			Addr:     redisMaster,
			Password: redisPassword,
			DB:       0,  // use default DB
		})
		
		_, err := redisClient.Ping().Result()
		if err != nil {
			log.Printf("Failed to ping Redis: %v. Check the Redis service is running", err)
			goapphealth="NOTGOOD"
		}
	}
	templates = template.Must(template.ParseGlob("templates/*.html"))
	r := mux.NewRouter()
	r.HandleFunc("/", indexHandler).Methods("GET")
	r.HandleFunc("/health", healthHandler).Methods("GET")
	http.Handle("/", r)
	http.ListenAndServe(":8080", r)
	
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	pagehits, err := redisClient.Incr("pagehits").Result()
	if err != nil {
		log.Printf("Failed to increment page counter: %v. Check the Redis service is running", err)
		goapphealth="REDIS PAGECOUNT FAILURE"
		pagehits = 0
	}

	templates.ExecuteTemplate(w, "index.html", pagehits)
	
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	
	templates.ExecuteTemplate(w, "health.html", goapphealth)
	
}

func getConsulKV(consulClient api.Client, key string) string {
	
	// Get a handle to the KV API
	kv := consulClient.KV()

	consulKey := "development/"+key

	appVar, _, err := kv.Get(consulKey, nil)
	if err != nil {
		log.Printf("Failed to read key value %v - Please ensure key value exists in consul : e.g. consul kv get %v >> %v",key,key, err)
		appVar, ok := os.LookupEnv(key)
		if ok {
			return appVar
		}
		log.Printf("Failed to read environment variable %v - Please ensure %v variable is set >> %v",key,key, err)
		return "FAIL"

	}

	return string(appVar.Value)
}

func getConsulSVC(consulClient api.Client, key string) string {
	
	var serviceDetail strings.Builder
	// get handle to catalog service api
	sd := consulClient.Catalog()

	myService, _, err := sd.Service(key, "", nil)
	if err != nil {
		log.Printf("Failed to discover Redis Service : e.g. curl http://localhost:8500/v1/catalog/service/redis >> %v", err)
		return "0:0"
	}
	serviceDetail.WriteString(string(myService[0].Address))
	serviceDetail.WriteString(":")
	serviceDetail.WriteString(strconv.Itoa(myService[0].ServicePort))

	return serviceDetail.String()
}
	

func redisInit() (string, string) {
	
	var redisService string
	var redisPassword string
	
	// Get a new client
	consulClient, err := api.NewClient(api.DefaultConfig())
	if err !=nil {
		log.Printf("Failed to contact consul - Please ensure both local agent and remote server are running : e.g. consul members >> %v", err)
		return "0", "0"
	}
	redisPassword = getConsulKV(*consulClient, "REDIS_MASTER_PASSWORD")
	redisService = getConsulSVC(*consulClient, "redis")
	if redisService == "0:0" {
		var serviceDetail strings.Builder
		redisHost := getConsulKV(*consulClient, "REDIS_MASTER_IP")
		redisPort := getConsulKV(*consulClient, "REDIS_HOST_PORT")
		serviceDetail.WriteString(redisHost)
		serviceDetail.WriteString(":")
		serviceDetail.WriteString(redisPort)
		redisService = serviceDetail.String()
	}
	
	return redisService, redisPassword

}

