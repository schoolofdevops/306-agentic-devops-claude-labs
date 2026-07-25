package faults

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/metrics"
)

type Config struct {
	Enabled         bool    `json:"enabled"`
	LatencyMs       int     `json:"latency_ms"`
	LatencyJitterMs int     `json:"latency_jitter_ms"`
	ErrorRate       float64 `json:"error_rate"`
	RateLimit       int     `json:"rate_limit"`
}

type Stats struct {
	LatencyInjected int64 `json:"latency_injected"`
	ErrorsInjected  int64 `json:"errors_injected"`
	RateLimited     int64 `json:"rate_limited"`
}

type Engine struct {
	mu    sync.RWMutex
	cfg   Config
	stats Stats
}

func NewEngine(cfg Config) *Engine {
	return &Engine{cfg: cfg}
}

func (e *Engine) GetConfig() Config {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.cfg
}

func (e *Engine) SetConfig(cfg Config) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.cfg = cfg
}

func (e *Engine) Clear() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.cfg = Config{}
	e.stats = Stats{}
}

func (e *Engine) GetStats() Stats {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.stats
}

var skipPrefixes = []string{"/healthz", "/readyz", "/metrics", "/admin/"}

func (e *Engine) Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			for _, prefix := range skipPrefixes {
				if strings.HasPrefix(r.URL.Path, prefix) {
					next.ServeHTTP(w, r)
					return
				}
			}

			e.mu.RLock()
			cfg := e.cfg
			e.mu.RUnlock()

			if !cfg.Enabled {
				next.ServeHTTP(w, r)
				return
			}

			if cfg.LatencyMs > 0 {
				delay := time.Duration(cfg.LatencyMs) * time.Millisecond
				if cfg.LatencyJitterMs > 0 {
					jitter := time.Duration(rand.Intn(cfg.LatencyJitterMs)) * time.Millisecond
					delay += jitter
				}
				time.Sleep(delay)
				e.mu.Lock()
				e.stats.LatencyInjected++
				e.mu.Unlock()
				metrics.FaultsInjected.WithLabelValues("latency").Inc()
			}

			if cfg.ErrorRate > 0 && rand.Float64() < cfg.ErrorRate {
				e.mu.Lock()
				e.stats.ErrorsInjected++
				e.mu.Unlock()
				metrics.FaultsInjected.WithLabelValues("error").Inc()
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(500)
				json.NewEncoder(w).Encode(map[string]string{
					"error": "injected fault",
					"type":  "error_rate",
				})
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
