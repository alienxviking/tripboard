from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Status = Literal["planned", "booked", "done"]


class TripIn(BaseModel):
    destination: str = Field(min_length=2, max_length=120)
    start_date: date
    end_date: date
    budget: float = Field(ge=0)
    status: Status = "planned"

    @model_validator(mode="after")
    def check_dates(self):
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self


class TripOut(TripIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
