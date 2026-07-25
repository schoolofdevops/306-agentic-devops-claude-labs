package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/handler"
	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/store"
)

func setup(t *testing.T) http.Handler {
	t.Helper()
	s, err := store.LoadFromFile("../../testdata/products.json")
	if err != nil {
		t.Fatalf("failed to load store: %v", err)
	}
	return handler.New(s)
}

func TestListProducts(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/api/v1/products", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var products []store.Product
	json.NewDecoder(w.Body).Decode(&products)
	if len(products) != 20 {
		t.Errorf("expected 20 products, got %d", len(products))
	}
}

func TestGetProduct(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/api/v1/products/PROD-001", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var p store.Product
	json.NewDecoder(w.Body).Decode(&p)
	if p.ID != "PROD-001" {
		t.Errorf("expected PROD-001, got %s", p.ID)
	}
}

func TestGetProduct_NotFound(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/api/v1/products/PROD-999", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 404 {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestReserveProduct(t *testing.T) {
	r := setup(t)
	body := strings.NewReader(`{"quantity": 2}`)
	req := httptest.NewRequest("POST", "/api/v1/products/PROD-001/reserve", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestReserveProduct_InsufficientStock(t *testing.T) {
	r := setup(t)
	body := strings.NewReader(`{"quantity": 9999}`)
	req := httptest.NewRequest("POST", "/api/v1/products/PROD-001/reserve", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 409 {
		t.Errorf("expected 409, got %d", w.Code)
	}
}

func TestInfo(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/api/v1/info", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var info map[string]interface{}
	json.NewDecoder(w.Body).Decode(&info)
	if _, ok := info["hostname"]; !ok {
		t.Error("expected hostname in info")
	}
	if _, ok := info["version"]; !ok {
		t.Error("expected version in info")
	}
}

func TestHealthz(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/healthz", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestReadyz(t *testing.T) {
	r := setup(t)
	req := httptest.NewRequest("GET", "/readyz", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Errorf("expected 200, got %d", w.Code)
	}
}
