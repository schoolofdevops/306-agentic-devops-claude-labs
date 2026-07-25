package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/handler"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/store"
)

func main() {
	port := envOr("PORT", "8081")
	dataPath := envOr("DATA_PATH", "testdata/products.json")

	s, err := store.LoadFromFile(dataPath)
	if err != nil {
		log.Fatalf("failed to load product data from %s: %v", dataPath, err)
	}
	log.Printf("loaded %d products from %s", len(s.List()), dataPath)

	r := handler.New(s)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("inventory-api starting on %s", addr)
	if err := http.ListenAndServe(addr, r); err != nil {
		log.Fatalf("server failed: %v", err)
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
