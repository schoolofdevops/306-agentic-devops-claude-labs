package store

import (
	"encoding/json"
	"errors"
	"os"
	"sync"
)

var (
	ErrNotFound          = errors.New("product not found")
	ErrInsufficientStock = errors.New("insufficient stock")
)

type Product struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
	Stock int     `json:"stock"`
}

type Store struct {
	mu       sync.RWMutex
	products map[string]*Product
	order    []string
}

func LoadFromFile(path string) (*Store, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var items []Product
	if err := json.Unmarshal(data, &items); err != nil {
		return nil, err
	}
	s := &Store{products: make(map[string]*Product), order: make([]string, 0, len(items))}
	for i := range items {
		s.products[items[i].ID] = &items[i]
		s.order = append(s.order, items[i].ID)
	}
	return s, nil
}

func (s *Store) List() []Product {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]Product, 0, len(s.order))
	for _, id := range s.order {
		result = append(result, *s.products[id])
	}
	return result
}

func (s *Store) Get(id string) (Product, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.products[id]
	if !ok {
		return Product{}, false
	}
	return *p, true
}

func (s *Store) Reserve(id string, qty int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.products[id]
	if !ok {
		return ErrNotFound
	}
	if p.Stock < qty {
		return ErrInsufficientStock
	}
	p.Stock -= qty
	return nil
}
