package faults_test

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/faults"
)

func TestEngine_Disabled(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: false, ErrorRate: 1.0})
	handler := e.Middleware()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	req := httptest.NewRequest("GET", "/test", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Errorf("expected 200 when disabled, got %d", w.Code)
	}
}

func TestEngine_ErrorInjection(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: true, ErrorRate: 1.0})
	handler := e.Middleware()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	req := httptest.NewRequest("GET", "/test", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	if w.Code != 500 {
		t.Errorf("expected 500 with 100%% error rate, got %d", w.Code)
	}
}

func TestEngine_LatencyInjection(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: true, LatencyMs: 100})
	handler := e.Middleware()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	req := httptest.NewRequest("GET", "/test", nil)
	w := httptest.NewRecorder()
	start := time.Now()
	handler.ServeHTTP(w, req)
	elapsed := time.Since(start)
	if elapsed < 90*time.Millisecond {
		t.Errorf("expected at least 90ms latency, got %v", elapsed)
	}
	if w.Code != 200 {
		t.Errorf("expected 200 with latency only, got %d", w.Code)
	}
}

func TestEngine_SetConfig(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: false})
	e.SetConfig(faults.Config{Enabled: true, ErrorRate: 0.5})
	cfg := e.GetConfig()
	if !cfg.Enabled {
		t.Error("expected enabled after SetConfig")
	}
	if cfg.ErrorRate != 0.5 {
		t.Errorf("expected ErrorRate 0.5, got %f", cfg.ErrorRate)
	}
}

func TestEngine_Clear(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: true, ErrorRate: 1.0})
	e.Clear()
	cfg := e.GetConfig()
	if cfg.Enabled {
		t.Error("expected disabled after Clear")
	}
}

func TestEngine_SkipsHealthEndpoints(t *testing.T) {
	e := faults.NewEngine(faults.Config{Enabled: true, ErrorRate: 1.0})
	handler := e.Middleware()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	for _, path := range []string{"/healthz", "/readyz", "/metrics", "/admin/faults"} {
		req := httptest.NewRequest("GET", path, nil)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
		if w.Code != 200 {
			t.Errorf("expected 200 for %s, got %d", path, w.Code)
		}
	}
}
