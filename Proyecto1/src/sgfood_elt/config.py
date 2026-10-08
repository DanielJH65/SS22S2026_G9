"""Configuración del pipeline.

- Credenciales: variables de entorno (archivo .env en local; entorno del
  contenedor en Airflow). Nunca se escriben en el código.
- Fuentes y modos de carga: config/pipeline.yaml.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[2]

# No sobrescribe variables ya definidas: en Airflow manda el entorno del contenedor.
load_dotenv(PROJECT_ROOT / ".env", override=False)


class ConfigError(RuntimeError):
    """Configuración faltante o inválida."""


@dataclass(frozen=True)
class DbConfig:
    host: str
    port: int
    dbname: str
    user: str
    password: str

    @classmethod
    def from_env(cls, prefix: str) -> "DbConfig":
        try:
            return cls(
                host=os.environ[f"{prefix}_HOST"],
                port=int(os.environ[f"{prefix}_PORT"]),
                dbname=os.environ[f"{prefix}_DB"],
                user=os.environ[f"{prefix}_USER"],
                password=os.environ[f"{prefix}_PASSWORD"],
            )
        except KeyError as exc:
            raise ConfigError(f"Falta la variable de entorno {exc.args[0]}") from exc


def oltp_config() -> DbConfig:
    return DbConfig.from_env("OLTP")


def dw_config() -> DbConfig:
    return DbConfig.from_env("DW")


def _resolve(path_str: str) -> Path:
    path = Path(path_str)
    return path if path.is_absolute() else PROJECT_ROOT / path


def data_dir() -> Path:
    return _resolve(os.getenv("DATA_DIR", "data"))


def load_pipeline_config() -> dict:
    path = _resolve(os.getenv("PIPELINE_CONFIG", "config/pipeline.yaml"))
    if not path.exists():
        raise ConfigError(f"No existe el archivo de configuración {path}")
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def find_oltp_table(cfg: dict, name: str) -> dict:
    for table in cfg["oltp"]["tables"]:
        if table["name"] == name:
            return table
    raise ConfigError(f"La tabla OLTP '{name}' no está en pipeline.yaml")


def find_csv_file(cfg: dict, file_name: str) -> dict:
    for entry in cfg["csv"]["files"]:
        if entry["file"] == file_name:
            return entry
    raise ConfigError(f"El archivo '{file_name}' no está en pipeline.yaml")
