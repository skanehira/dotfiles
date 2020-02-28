package main

import (
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Hello Gorilla"))
	})

	log.Fatal(http.ListenAndServe(":{{_input_:port}}", nil))
}
