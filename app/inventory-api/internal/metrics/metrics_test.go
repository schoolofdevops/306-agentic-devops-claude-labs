package metrics_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/metrics"
)

func TestMiddleware_RecordsRequestMetrics(t *testing.T) {
	metrics.Register()

	r := chi.NewRouter()
	r.Use(metrics.Middleware())
	r.Get("/api/v1/products/{id}", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	})
	r.Handle("/metrics", metrics.Handler())

	req := httptest.NewRequest("GET", "/api/v1/products/PROD-001", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	req2 := httptest.NewRequest("GET", "/metrics", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)

	body := w2.Body.String()
	if !strings.Contains(body, "inventory_api_requests_total") {
		t.Errorf("expected inventory_api_requests_total in metrics output, got: %s", body)
	}
	if !strings.Contains(body, "inventory_api_request_duration_seconds") {
		t.Errorf("expected inventory_api_request_duration_seconds in metrics output")
	}
	if !strings.Contains(body, `path="/api/v1/products/{id}"`) {
		t.Errorf("expected route pattern label in metrics output, got: %s", body)
	}
}

func TestMiddleware_SkipsMetricsEndpoint(t *testing.T) {
	metrics.Register()

	r := chi.NewRouter()
	r.Use(metrics.Middleware())
	r.Handle("/metrics", metrics.Handler())

	req := httptest.NewRequest("GET", "/metrics", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200 from /metrics, got %d", w.Code)
	}
}
