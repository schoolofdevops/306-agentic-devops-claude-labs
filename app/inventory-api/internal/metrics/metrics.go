package metrics

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	RequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "inventory_api_requests_total",
			Help: "Total HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	RequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "inventory_api_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	FaultsInjected = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "inventory_api_faults_injected_total",
			Help: "Total faults injected",
		},
		[]string{"type"},
	)

	StockReservations = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "inventory_api_stock_reservations_total",
			Help: "Total stock reservation attempts",
		},
		[]string{"status"},
	)
)

var registerOnce sync.Once

func Register() {
	registerOnce.Do(func() {
		prometheus.MustRegister(RequestsTotal, RequestDuration, FaultsInjected, StockReservations)
	})
}

func Handler() http.Handler {
	return promhttp.Handler()
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.statusCode = code
	r.ResponseWriter.WriteHeader(code)
}

func Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/metrics" {
				next.ServeHTTP(w, r)
				return
			}

			start := time.Now()
			rec := &statusRecorder{ResponseWriter: w, statusCode: 200}
			next.ServeHTTP(rec, r)
			duration := time.Since(start).Seconds()

			routePattern := chi.RouteContext(r.Context()).RoutePattern()
			if routePattern == "" {
				routePattern = r.URL.Path
			}

			RequestsTotal.WithLabelValues(r.Method, routePattern, strconv.Itoa(rec.statusCode)).Inc()
			RequestDuration.WithLabelValues(r.Method, routePattern).Observe(duration)
		})
	}
}
