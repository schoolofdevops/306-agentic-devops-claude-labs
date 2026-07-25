package store_test

import (
	"testing"

	"github.com/schoolofdevops/agentic-ops-lab/app/inventory-api/internal/store"
)

func seedStore(t *testing.T) *store.Store {
	t.Helper()
	s, err := store.LoadFromFile("../../testdata/products.json")
	if err != nil {
		t.Fatalf("failed to load seed data: %v", err)
	}
	return s
}

func TestList(t *testing.T) {
	s := seedStore(t)
	products := s.List()
	if len(products) != 20 {
		t.Errorf("expected 20 products, got %d", len(products))
	}
}

func TestGet_Exists(t *testing.T) {
	s := seedStore(t)
	p, ok := s.Get("PROD-001")
	if !ok {
		t.Fatal("expected PROD-001 to exist")
	}
	if p.Name != "Campaign T-Shirt (S)" {
		t.Errorf("unexpected name: %s", p.Name)
	}
}

func TestGet_NotFound(t *testing.T) {
	s := seedStore(t)
	_, ok := s.Get("PROD-999")
	if ok {
		t.Error("expected PROD-999 to not exist")
	}
}

func TestReserve_Success(t *testing.T) {
	s := seedStore(t)
	err := s.Reserve("PROD-001", 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	p, _ := s.Get("PROD-001")
	if p.Stock != 145 {
		t.Errorf("expected stock 145, got %d", p.Stock)
	}
}

func TestReserve_InsufficientStock(t *testing.T) {
	s := seedStore(t)
	err := s.Reserve("PROD-020", 100)
	if err == nil {
		t.Fatal("expected error for insufficient stock")
	}
	if err != store.ErrInsufficientStock {
		t.Errorf("expected ErrInsufficientStock, got %v", err)
	}
}

func TestReserve_NotFound(t *testing.T) {
	s := seedStore(t)
	err := s.Reserve("PROD-999", 1)
	if err == nil {
		t.Fatal("expected error for missing product")
	}
	if err != store.ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}
