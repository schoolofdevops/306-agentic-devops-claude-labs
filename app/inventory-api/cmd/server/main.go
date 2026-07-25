package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/faults"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/handler"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/metrics"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/store"
)

func main() {
	metrics.Register()

	port := envOr("PORT", "8081")
	dataPath := envOr("DATA_PATH", "testdata/products.json")

	s, err := store.LoadFromFile(dataPath)
	if err != nil {
		log.Fatalf("failed to load product data from %s: %v", dataPath, err)
	}
	log.Printf("loaded %d products from %s", len(s.List()), dataPath)

	fe := faults.NewEngine(faults.Config{
		Enabled:         envOr("FAULT_ENABLED", "false") == "true",
		LatencyMs:       envInt("FAULT_LATENCY_MS", 0),
		LatencyJitterMs: envInt("FAULT_LATENCY_JITTER_MS", 0),
		ErrorRate:       envFloat("FAULT_ERROR_RATE", 0.0),
		RateLimit:       envInt("FAULT_RATE_LIMIT", 0),
	})

	r := handler.New(s, fe)

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

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func envFloat(key string, fallback float64) float64 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return fallback
	}
	return f
}
