package handler

import (
	"encoding/json"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/faults"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/metrics"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/store"
)

type reserveRequest struct {
	Quantity int `json:"quantity"`
}

func New(s *store.Store, fe *faults.Engine) chi.Router {
	r := chi.NewRouter()

	r.Use(metrics.Middleware())
	r.Use(fe.Middleware())

	r.Handle("/metrics", metrics.Handler())

	r.Get("/admin/faults", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]interface{}{
			"config": fe.GetConfig(),
			"stats":  fe.GetStats(),
		})
	})

	r.Post("/admin/faults", func(w http.ResponseWriter, r2 *http.Request) {
		var cfg faults.Config
		if err := json.NewDecoder(r2.Body).Decode(&cfg); err != nil {
			writeJSON(w, 400, map[string]string{"error": "invalid request body"})
			return
		}
		fe.SetConfig(cfg)
		writeJSON(w, 200, map[string]interface{}{"status": "updated", "config": fe.GetConfig()})
	})

	r.Delete("/admin/faults", func(w http.ResponseWriter, _ *http.Request) {
		fe.Clear()
		writeJSON(w, 200, map[string]string{"status": "cleared"})
	})

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})

	r.Get("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if s == nil {
			writeJSON(w, 503, map[string]string{"status": "not ready", "reason": "store not initialized"})
			return
		}
		writeJSON(w, 200, map[string]string{"status": "ready"})
	})

	r.Get("/api/v1/info", func(w http.ResponseWriter, _ *http.Request) {
		hostname, _ := os.Hostname()
		version := envOr("APP_VERSION", "1.0.0")
		writeJSON(w, 200, map[string]interface{}{
			"service":    "inventory-api",
			"version":    version,
			"hostname":   hostname,
			"container":  fileExists("/.dockerenv"),
			"kubernetes": os.Getenv("KUBERNETES_SERVICE_HOST") != "",
			"namespace":  os.Getenv("POD_NAMESPACE"),
			"pod":        os.Getenv("POD_NAME"),
		})
	})

	r.Get("/api/v1/products", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, s.List())
	})

	r.Get("/api/v1/products/{id}", func(w http.ResponseWriter, r2 *http.Request) {
		id := chi.URLParam(r2, "id")
		p, ok := s.Get(id)
		if !ok {
			writeJSON(w, 404, map[string]string{"error": "product not found"})
			return
		}
		writeJSON(w, 200, p)
	})

	r.Post("/api/v1/products/{id}/reserve", func(w http.ResponseWriter, r2 *http.Request) {
		id := chi.URLParam(r2, "id")
		var req reserveRequest
		if err := json.NewDecoder(r2.Body).Decode(&req); err != nil {
			writeJSON(w, 400, map[string]string{"error": "invalid request body"})
			return
		}
		if req.Quantity <= 0 {
			writeJSON(w, 400, map[string]string{"error": "quantity must be positive"})
			return
		}
		if err := s.Reserve(id, req.Quantity); err != nil {
			switch err {
			case store.ErrNotFound:
				metrics.StockReservations.WithLabelValues("not_found").Inc()
				writeJSON(w, 404, map[string]string{"error": "product not found"})
			case store.ErrInsufficientStock:
				metrics.StockReservations.WithLabelValues("insufficient").Inc()
				writeJSON(w, 409, map[string]string{"error": "insufficient stock"})
			default:
				metrics.StockReservations.WithLabelValues("error").Inc()
				writeJSON(w, 500, map[string]string{"error": "internal error"})
			}
			return
		}
		metrics.StockReservations.WithLabelValues("success").Inc()
		p, _ := s.Get(id)
		writeJSON(w, 200, map[string]interface{}{
			"status":          "reserved",
			"product_id":      id,
			"quantity":        req.Quantity,
			"remaining_stock": p.Stock,
		})
	})

	return r
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
