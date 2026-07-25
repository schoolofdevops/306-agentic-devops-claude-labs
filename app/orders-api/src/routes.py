import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession
from src.database import get_db
from src.inventory_client import InventoryClient
from src.config import Settings

logger = logging.getLogger("orders-api.routes")
settings = Settings()
inventory_client = InventoryClient(settings)

router = APIRouter(prefix="/api/v1")


class CreateOrderRequest(BaseModel):
    product_id: str = Field(..., min_length=1)
    quantity: int = Field(..., gt=0)


class OrderResponse(BaseModel):
    id: int
    product_id: str
    quantity: int
    status: str
    created_at: str | None = None

    model_config = {"from_attributes": True}


@router.get("/orders")
async def list_orders(limit: int = 20, db: AsyncSession = Depends(get_db)):
    from src.models import Order
    try:
        result = await db.execute(
            select(Order).order_by(desc(Order.created_at)).limit(limit)
        )
    except Exception as e:
        logger.error(f"database unavailable: {e}")
        raise HTTPException(status_code=503, detail=f"database unavailable: {e}")
    orders = result.scalars().all()
    return [
        {
            "id": o.id,
            "product_id": o.product_id,
            "quantity": o.quantity,
            "status": o.status,
            "created_at": o.created_at.isoformat() if o.created_at else None,
        }
        for o in orders
    ]


@router.post("/orders", status_code=201)
async def create_order(req: CreateOrderRequest, db: AsyncSession = Depends(get_db)):
    from src.models import Order

    try:
        stock = await inventory_client.check_stock(req.product_id)
    except Exception as e:
        logger.error(f"inventory check failed: {e}")
        raise HTTPException(status_code=503, detail=f"inventory service unavailable: {e}")

    if stock.get("stock", 0) < req.quantity:
        raise HTTPException(status_code=409, detail="insufficient stock")

    try:
        reserve_result = await inventory_client.reserve(req.product_id, req.quantity)
    except Exception as e:
        logger.error(f"inventory reserve failed: {e}")
        raise HTTPException(status_code=503, detail=f"inventory service unavailable: {e}")

    order = Order(
        product_id=req.product_id,
        quantity=req.quantity,
        status="completed",
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)

    return {
        "id": order.id,
        "product_id": order.product_id,
        "quantity": order.quantity,
        "status": order.status,
        "remaining_stock": reserve_result.get("remaining_stock"),
    }


@router.get("/orders/{order_id}")
async def get_order(order_id: int, db: AsyncSession = Depends(get_db)):
    from src.models import Order
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="order not found")
    return {
        "id": order.id,
        "product_id": order.product_id,
        "quantity": order.quantity,
        "status": order.status,
        "created_at": order.created_at.isoformat() if order.created_at else None,
    }


@router.get("/products")
async def list_products():
    try:
        return await inventory_client.list_products()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"inventory service unavailable: {e}")
