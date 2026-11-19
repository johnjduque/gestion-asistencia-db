"""Generador del conjunto de datos de prueba variado de AsistenciasUCO (laboratorio local).

Produce, junto a este archivo:
  01_estructura.sql   personas, roles, facultades, programas, planes, asignaturas, periodos, grupos, horarios, matriculas
  02_sesiones.sql     sesiones de 2026-2 con el generador real (usp_generar_sesiones_grupo_v2) y de 2026-1 con festivos
  03_asistencia.sql   historial de tomas y asistencia con porcentajes controlados por matricula
  04_flujos.sql       alertas, revisiones de cancelacion, retiro, reclamos y solicitudes de sesion con los SP reales
  usuarios_datos_prueba.json   usuarios para el componente de Seguridad (Keycloak + PDP)
  USUARIOS.md         directorio legible de usuarios por rol (sin contrasenas)

Se ejecuta sobre una base recien desplegada con deploy_schema.ps1. Los identificadores son deterministas (uuid5), asi
que volver a generar produce los mismos archivos. Uso:  python -X utf8 generar_datos_prueba.py
"""
import json
import os
import unicodedata
import uuid
from datetime import time

HERE = os.path.dirname(os.path.abspath(__file__))
NS = uuid.UUID("6f1c2a7e-3b4d-4c5e-9f60-a1b2c3d4e5f6")
INSTITUCION = "B1C2D3E4-0000-0000-0000-000000000001"
PASSWORD_PLACEHOLDER = "HashBackend_AbCdEf1234567890"  # igual que las semillas: la autenticacion vive en Keycloak


def gid(kind, key):
    return str(uuid.uuid5(NS, f"{kind}:{key}")).upper()


def ascii_low(text):
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn").lower().replace(" ", "")


def q(text):
    return "N'" + str(text).replace("'", "''") + "'"


# ── Personas ────────────────────────────────────────────────────────────────────────────────────────────────────
# (clave, primerNombre, segundoNombre, primerApellido, segundoApellido, overrides)
CANON = {  # usuarios canonicos de las semillas: conservan id, correo y usuario de Keycloak
    "ADMIN": dict(uid="E1F2A3B4-0000-0000-0000-000000000000", rid="F1A2B3C4-0000-0000-0000-000000000000",
                  correo="admin.institucional@uco.edu.co", username="uco-administrador", numero=1017445500),
    "D-ING": dict(uid="E1F2A3B4-0000-0000-0000-000000000001", rid="F1A2B3C4-0000-0000-0000-000000000001",
                  correo="decano.ingenieria@uco.edu.co", username="uco-decano", numero=1017000001),
    "C-SIS": dict(uid="E1F2A3B4-0000-0000-0000-000000000002", rid="F1A2B3C4-0000-0000-0000-000000000002",
                  correo="coordinador.sistemas@uco.edu.co", username="uco-coordinador", numero=1017000002),
    "T-MAR": dict(uid="E1F2A3B4-0000-0000-0000-000000000003", rid="F1A2B3C4-0000-0000-0000-000000000003",
                  correo="maria.rostagno@uco.edu.co", username="uco-docente", numero=1017112233),
    "E-CARLOS": dict(uid="E1F2A3B4-0000-0000-0000-000000000004", rid="F1A2B3C4-0000-0000-0000-000000000004",
                     correo="carlos.zapata@uco.edu.co", username="uco-estudiante", numero=1017223344),
    "E-ANA": dict(uid="E1F2A3B4-0000-0000-0000-000000000005", rid="F1A2B3C4-0000-0000-0000-000000000005",
                  correo="ana.gomez@uco.edu.co", numero=1017334455),
}

ADMIN = [("ADMIN", "Gabriel", "Esteban", "Vélez", "Uribe")]
DECANOS = [  # (clave, nombres..., facultad o None)
    ("D-ING", "Jorge", "Iván", "Restrepo", "Gil", "F-ING"),
    ("D-ECA", "Luz", "Marina", "Cardona", "Ríos", "F-ECA"),
    ("D-SOC", "Hernán", "Darío", "Valencia", "Mejía", "F-SOC"),
    ("D-SAL", "Paula", "Andrea", "Zuluaga", "Henao", "F-SAL"),
    ("D-LIB", "Andrés", "Felipe", "Ospina", "Arango", None),
]
COORDINADORES = [  # (clave, nombres..., facultad, activo)
    ("C-SIS", "Natalia", "", "Gómez", "Arbeláez", "F-ING", True),
    ("C-IND", "Carlos", "Mario", "Jaramillo", "Duque", "F-ING", True),
    ("C-TDS", "Diana", "Marcela", "Londoño", "Vélez", "F-ING", True),
    ("C-ADM", "Juan", "Pablo", "Henao", "Correa", "F-ECA", True),
    ("C-CON", "Sandra", "Milena", "Ocampo", "Giraldo", "F-ECA", True),
    ("C-ESP", "Ricardo", "Alonso", "Betancur", "Salazar", "F-ECA", True),
    ("C-PSI", "Lina", "María", "Agudelo", "Franco", "F-SOC", True),
    ("C-ING2", "Mauricio", "Alejandro", "Quintero", "Ramírez", "F-ING", True),
    ("C-ECA2", "Claudia", "Patricia", "Montoya", "Echeverri", "F-ECA", True),
    ("C-SOC2", "Esteban", "", "Rendón", "Castaño", "F-SOC", False),
]
# Docentes: (clave, nombres..., [(programa, vinculacion, activo)]). T-DIA es la misma persona que C-TDS.
DOCENTES = [
    ("T-MAR", "María", "Elena", "Rostagno", "Valencia", [("P-SIS", "PLA", 1), ("P-TDS", "CAT", 1)]),
    ("T-FEL", "Felipe", "Andrés", "Castaño", "Ruiz", [("P-SIS", "PLA", 1), ("P-TDS", "CAT", 1), ("P-IND", "CAT", 1)]),
    ("T-GLO", "Gloria", "Inés", "Marín", "Sánchez", [("P-SIS", "PLA", 1), ("P-IND", "PLA", 1), ("P-TDS", "PLA", 1)]),
    ("T-SEB", "Sebastián", "", "Toro", "Alzate", [("P-TDS", "OCA", 1)]),
    ("T-DIA", None, None, None, None, [("P-TDS", "MTI", 1)]),
    ("T-ADR", "Adriana", "Lucía", "Vargas", "Botero", [("P-IND", "PLA", 1), ("P-ADM", "CAT", 1), ("P-CON", "CAT", 1), ("P-PSI", "CAT", 1)]),
    ("T-OSC", "Óscar", "Eduardo", "Patiño", "Mesa", [("P-CON", "PLA", 1), ("P-ADM", "CAT", 1), ("P-IND", "CAT", 1), ("P-PSI", "CAT", 1)]),
    ("T-BEA", "Beatriz", "Elena", "Arango", "Pineda", [("P-ADM", "PLA", 1)]),
    ("T-HUG", "Hugo", "Alberto", "Serna", "López", [("P-CON", "PLA", 1), ("P-ADM", "MTI", 1), ("P-ESP", "CAT", 1)]),
    ("T-MON", "Mónica", "Isabel", "Ruiz", "Tobón", [("P-ESP", "OCA", 1)]),
    ("T-CAM", "Camilo", "Andrés", "Bedoya", "Muñoz", [("P-PSI", "PLA", 1)]),
    ("T-TER", "Teresa", "de Jesús", "Gallego", "Orozco", [(p, "CAT", 1) for p in ("P-SIS", "P-IND", "P-TDS", "P-ADM", "P-CON", "P-PSI")]),
    ("T-ALE", "Alejandro", "José", "Cárdenas", "Villa", [(p, "PLA", 1) for p in ("P-SIS", "P-IND", "P-TDS", "P-ADM", "P-CON", "P-PSI")]),
    ("T-JUL", "Julián", "David", "Hoyos", "Montes", [("P-SIS", "CAT", 1), ("P-TDS", "CAT", 1)]),
    ("T-LIL", "Liliana", "Patricia", "Mejía", "Osorio", [("P-ADM", "OCA", 0)]),
    ("T-FER", "Fernando", "León", "Ríos", "Cifuentes", [("P-PSI", "CAT", 1)]),
]

# ── Estructura academica ────────────────────────────────────────────────────────────────────────────────────────
FACULTADES = [  # (clave, id, nombre)
    ("F-ING", "A2B3C4D5-0000-0000-0000-000000000001", "Facultad de Ingeniería"),
    ("F-ECA", None, "Facultad de Ciencias Económicas y Administrativas"),
    ("F-SOC", None, "Facultad de Ciencias Sociales"),
    ("F-SAL", None, "Facultad de Ciencias de la Salud"),
]
PROGRAMAS = [  # (clave, id, facultad, tipo, nombre, coordinador, modalidad, jornada, semestres, planId)
    # Plan 2024 de 9 semestres (el plan 2018 inactivo tenia 10): deja cupo para probar "anadir semestre" (el catalogo llega a S10).
    ("P-SIS", "B2C3D4E5-0000-0000-0000-000000000001", "F-ING", "PRE", "Ingeniería de Sistemas", "C-SIS", "PRE", "DIU", 9,
     "C2D3E4F5-0000-0000-0000-000000000001"),
    ("P-IND", None, "F-ING", "PRE", "Ingeniería Industrial", "C-IND", "PRE", "DIU", 10, None),
    ("P-TDS", None, "F-ING", "PRE", "Tecnología en Desarrollo de Software", "C-TDS", "PRE", "NOC", 6, None),
    ("P-ADM", None, "F-ECA", "PRE", "Administración de Empresas", "C-ADM", "PRE", "DIU", 10, None),
    ("P-CON", None, "F-ECA", "PRE", "Contaduría Pública", "C-CON", "PRE", "NOC", 10, None),
    ("P-ESP", None, "F-ECA", "POS", "Especialización en Gerencia de Proyectos", "C-ESP", "HIB", "FDS", 2, None),
    ("P-PSI", None, "F-SOC", "PRE", "Psicología", "C-PSI", "PRE", "DIU", 10, None),
]
AREAS = [("ISW", "Ingenieria de Software", "C1D2E3F4-0000-0000-0000-000000000001"),
         ("CBA", "Ciencias Básicas", None), ("HUM", "Humanidades", None), ("ADM", "Administración", None),
         ("CON", "Contabilidad y Finanzas", None), ("IND", "Producción y Operaciones", None),
         ("PSI", "Psicología", None), ("PRY", "Gerencia de Proyectos", None)]
PRE6 = ("P-SIS", "P-IND", "P-TDS", "P-ADM", "P-CON", "P-PSI")
ASIGNATURAS = [  # (codigo, nombre, creditos, area, componente, [(programa, semestre, caracter)])
    ("INS-101", "Cátedra Institucional UCO", 2, "HUM", "INS", [(p, 1, "OBL") for p in PRE6]),
    ("INS-102", "Ética y Humanismo", 2, "HUM", "INS", [(p, 2, "OBL") for p in PRE6]),
    ("INS-103", "Constitución Política", 2, "HUM", "INS",
     [("P-SIS", 3, "OBL"), ("P-IND", 3, "OBL"), ("P-TDS", 2, "OBL"), ("P-ADM", 2, "OBL"), ("P-CON", 2, "OBL"), ("P-PSI", 3, "OPT")]),
    ("MAT-101", "Cálculo Diferencial", 4, "CBA", "BAS", [("P-SIS", 1, "OBL"), ("P-IND", 1, "OBL"), ("P-TDS", 1, "OBL")]),
    ("MAT-102", "Álgebra Lineal", 3, "CBA", "BAS", [("P-SIS", 2, "OBL"), ("P-IND", 2, "OBL")]),
    ("EST-201", "Estadística General", 3, "CBA", "BAS", [("P-IND", 3, "OBL"), ("P-ADM", 3, "OBL"), ("P-CON", 3, "OBL"), ("P-PSI", 3, "OBL")]),
    ("FIN-201", "Matemáticas Financieras", 3, "CON", "BAS", [("P-ADM", 3, "OBL"), ("P-CON", 3, "OBL")]),
    ("SIS-301", "Desarrollo Web", 3, "ISW", "ESP", [("P-SIS", 5, "OBL"), ("P-TDS", 3, "OBL")]),
    ("CON-301", "Costos y Presupuestos", 3, "CON", "ESP", [("P-ADM", 5, "OBL"), ("P-CON", 4, "OBL"), ("P-ESP", 1, "OBL")]),
    ("SIS-101", "Programación I", 4, "ISW", "ESP", [("P-SIS", 1, "OBL")]),
    ("SIS-201", "Bases de Datos", 4, "ISW", "ESP", [("P-SIS", 3, "OBL")]),
    ("ARQ-402", "Arquitectura de Software", 3, "ISW", "ESP", [("P-SIS", 8, "OBL")]),
    ("IND-301", "Investigación de Operaciones", 3, "IND", "ESP", [("P-IND", 5, "OBL")]),
    ("IND-302", "Gestión de la Calidad", 3, "IND", "ESP", [("P-IND", 6, "OBL")]),
    ("TDS-101", "Fundamentos de Programación", 3, "ISW", "ESP", [("P-TDS", 1, "OBL")]),
    ("TDS-201", "Pruebas de Software", 3, "ISW", "ESP", [("P-TDS", 4, "OBL")]),
    ("ADM-101", "Fundamentos de Administración", 3, "ADM", "ESP", [("P-ADM", 1, "OBL")]),
    ("ADM-201", "Mercadeo", 3, "ADM", "ESP", [("P-ADM", 4, "OBL")]),
    ("CON-101", "Contabilidad Financiera", 4, "CON", "ESP", [("P-CON", 1, "OBL")]),
    ("PSI-201", "Psicología del Desarrollo", 3, "PSI", "ESP", [("P-PSI", 2, "OBL")]),
    ("PSI-301", "Psicometría", 3, "PSI", "ESP", [("P-PSI", 4, "OBL")]),
    ("GPR-501", "Formulación y Evaluación de Proyectos", 3, "PRY", "ESP", [("P-ESP", 1, "OBL")]),
]
ASIG_ID = {"ARQ-402": "E2F3A4B5-0000-0000-0000-000000000001"}
APE_ID = {("ARQ-402", "P-SIS", 8): "E2F3A4B5-0001-0000-0000-000000000001"}
SPE_ID = {("P-SIS", 8): "D2E3F4A5-0000-0000-0000-000000000001"}
PERIODOS = [  # (clave, id, nombre, codigo, inicio, fin, anio)
    ("P20261", None, "2026-1", 20261, "2026-02-02", "2026-06-12", 2026),
    ("P20262", "F2A3B4C5-0000-0000-0000-000000000001", "2026-2", 20262, "2026-08-01", "2026-12-15", 2026),
    ("P20271", None, "2027-1", 20271, "2027-02-01", "2027-06-11", 2027),
]


def h(a, b):
    return (time(int(a), int(round((a % 1) * 60))), time(int(b), int(round((b % 1) * 60))))


# Grupos: (clave, asignatura, codigo, docente, periodo, [(dia, ini, fin)], cupo (None = 30 / calculado))
GRUPOS = [
    ("CAT-1", "INS-101", 1, "T-TER", "P20262", [("LU", 7, 9)], 35),
    ("CAT-2", "INS-101", 2, "T-TER", "P20262", [("MI", 14, 16)], 35),
    ("CAT-3", "INS-101", 3, "T-TER", "P20262", [("MI", 20, 22)], 30),
    ("ETI-1", "INS-102", 1, "T-ALE", "P20262", [("JU", 9, 11)], 35),
    ("ETI-2", "INS-102", 2, "T-ALE", "P20262", [("JU", 20, 22)], 30),
    ("CPO-1", "INS-103", 1, "T-ALE", "P20262", [("VI", 7, 9)], 35),
    ("CPO-2", "INS-103", 2, "T-ALE", "P20262", [("LU", 20, 22)], 30),
    ("CAL-1", "MAT-101", 1, "T-GLO", "P20262", [("MA", 7, 9), ("JU", 7, 9)], 30),
    ("CAL-2", "MAT-101", 2, "T-GLO", "P20262", [("LU", 9, 11), ("MI", 9, 11)], 30),
    ("CAL-3", "MAT-101", 3, "T-GLO", "P20262", [("LU", 18, 20), ("MI", 18, 20)], 25),
    ("ALG-1", "MAT-102", 1, "T-FEL", "P20262", [("MA", 14, 16), ("JU", 14, 16)], 30),
    ("EST-1", "EST-201", 1, "T-ADR", "P20262", [("LU", 11, 13), ("MI", 11, 13)], 35),
    ("EST-2", "EST-201", 2, "T-OSC", "P20262", [("MA", 18, 20), ("JU", 18, 20)], 30),
    ("MFI-1", "FIN-201", 1, "T-OSC", "P20262", [("MI", 9, 11), ("VI", 9, 11)], 30),
    ("MFI-2", "FIN-201", 2, "T-OSC", "P20262", [("MA", 20, 22)], 30),
    ("DWB-1", "SIS-301", 1, "T-MAR", "P20262", [("MA", 16, 18), ("JU", 16, 18)], 30),
    ("DWB-2", "SIS-301", 2, "T-FEL", "P20262", [("MA", 20, 22)], 25),
    ("COS-1", "CON-301", 1, "T-HUG", "P20262", [("MA", 14, 16), ("JU", 14, 16)], 30),
    ("COS-2", "CON-301", 2, "T-HUG", "P20262", [("VI", 18, 22)], 30),
    ("COS-3", "CON-301", 3, "T-HUG", "P20262", [("SA", 7, 10)], 20),
    ("PRG-1", "SIS-101", 1, "T-MAR", "P20262", [("LU", 11, 13), ("MI", 11, 13)], 30),
    ("PRG-2", "SIS-101", 2, "T-MAR", "P20262", [("MA", 9, 11), ("VI", 9, 11)], 30),
    ("BDA-1", "SIS-201", 1, "T-FEL", "P20262", [("MA", 11, 13), ("JU", 11, 13)], 30),
    ("ARQ-1", "ARQ-402", 1, "T-MAR", "P20262", [("LU", 14, 16), ("MI", 16, 18)], 30),
    ("IOP-1", "IND-301", 1, "T-ADR", "P20262", [("MA", 11, 13), ("VI", 11, 13)], 30),
    ("GCA-1", "IND-302", 1, "T-ADR", "P20262", [("LU", 16, 18), ("MI", 16, 18)], "LLENO"),
    ("FPR-1", "TDS-101", 1, "T-SEB", "P20262", [("MA", 18, 20), ("JU", 18, 20)], 25),
    ("PRU-1", "TDS-201", 1, "T-DIA", "P20262", [("VI", 18, 22)], 25),
    ("FAD-1", "ADM-101", 1, "T-BEA", "P20262", [("LU", 9, 11), ("JU", 11, 13)], 30),
    ("MER-1", "ADM-201", 1, "T-BEA", "P20262", [("MA", 9, 11), ("VI", 14, 16)], 30),
    ("CTB-1", "CON-101", 1, "T-HUG", "P20262", [("LU", 18, 20), ("MI", 18, 20)], 30),
    ("PSD-1", "PSI-201", 1, "T-CAM", "P20262", [("MA", 7, 9), ("JU", 7, 9)], 30),
    ("PSM-1", "PSI-301", 1, "T-CAM", "P20262", [("MA", 14, 16), ("VI", 14, 16)], "CASI"),
    ("GPR-1", "GPR-501", 1, "T-MON", "P20262", [("SA", 10, 13)], 20),
    # 2026-1: periodo terminado SIN cierre masivo (matriculas aun activas) para probar el cierre y el historial
    ("H-PRG", "SIS-101", 1, "T-MAR", "P20261", [("LU", 11, 13), ("MI", 11, 13)], 30),
    ("H-CAL", "MAT-101", 1, "T-GLO", "P20261", [("MA", 7, 9), ("JU", 7, 9)], 30),
    ("H-FAD", "ADM-101", 1, "T-BEA", "P20261", [("LU", 9, 11), ("JU", 11, 13)], 30),
    ("H-CTB", "CON-101", 1, "T-HUG", "P20261", [("LU", 18, 20), ("MI", 18, 20)], 30),
    ("H-PSD", "PSI-201", 1, "T-CAM", "P20261", [("MA", 7, 9), ("JU", 7, 9)], 30),
    ("H-FPR", "TDS-101", 1, "T-SEB", "P20261", [("MA", 18, 20), ("JU", 18, 20)], 25),
]
GRUPO_ID = {"ARQ-1": "A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D"}  # grupo de la semilla 14 (lo usan pruebas E2E)

# Estudiantes: (clave, nombres..., [programas], [grupos 2026-2], [grupos 2026-1], correoConfirmado)
SIS_A1 = ["CAT-1", "CAL-1", "PRG-1", "ALG-1", "ETI-1"]
SIS_A2 = ["CAT-1", "CAL-2", "PRG-2", "ALG-1", "ETI-1"]
SIS_B = ["BDA-1", "ARQ-1", "DWB-1", "CPO-1", "ETI-1"]
IND_A1 = ["CAT-1", "CAL-1", "ALG-1", "ETI-1", "CPO-1"]
IND_A2 = ["CAT-1", "CAL-2", "ALG-1", "ETI-1", "CPO-1"]
IND_B = ["EST-1", "IOP-1", "GCA-1", "ETI-1", "CPO-1"]
TDS_A = ["CAT-3", "CAL-3", "FPR-1", "CPO-2", "ETI-2"]
TDS_B = ["DWB-2", "PRU-1", "ETI-2", "CPO-2", "CAT-3"]
ADM_A = ["CAT-2", "FAD-1", "ETI-1", "CPO-1", "EST-1"]
ADM_B = ["MFI-1", "COS-1", "MER-1", "EST-1", "ETI-1"]
CON_A = ["CAT-3", "CTB-1", "CPO-2", "ETI-2", "EST-2"]
CON_B = ["MFI-2", "COS-2", "EST-2", "ETI-2", "CPO-2"]
PSI_A = ["CAT-1", "PSD-1", "ETI-1", "EST-1", "CPO-1"]
PSI_B = ["CAT-2", "PSM-1", "EST-1", "ETI-1", "CPO-1"]
ESP = ["COS-3", "GPR-1"]
ESTUDIANTES = [
    ("E-CARLOS", "Carlos", "Andrés", "Zapata", "Gómez", ["P-SIS"], SIS_B, ["H-PRG"], 1),
    ("E-ANA", "Ana", "Sofía", "Gómez", "Ríos", ["P-SIS"], SIS_B, ["H-PRG"], 1),
    ("E-SANTIAGO", "Santiago", "Alejandro", "Restrepo", "Mora", ["P-SIS"], SIS_B, ["H-PRG"], 1),
    ("E-VALENTINA", "Valentina", "", "Isaza", "Cárdenas", ["P-SIS"], SIS_B, ["H-PRG"], 1),
    ("E-MATEO", "Mateo", "", "Giraldo", "Herrera", ["P-SIS"], SIS_A1, [], 1),
    ("E-ISABELLA", "Isabella", "", "Montoya", "Salazar", ["P-SIS"], SIS_A1, [], 1),
    ("E-SAMUEL", "Samuel", "David", "Ochoa", "Pérez", ["P-SIS"], SIS_A2, [], 1),
    ("E-MARIANA", "Mariana", "", "Echeverri", "Gil", ["P-SIS"], SIS_A2, [], 1),
    ("E-TOMAS", "Tomás", "", "Arango", "Duque", ["P-IND"], IND_A1, [], 1),
    ("E-SARA", "Sara", "Lucía", "Henao", "Vélez", ["P-IND"], IND_A2, [], 1),
    ("E-JERONIMO", "Jerónimo", "", "Castaño", "Muñoz", ["P-IND"], IND_A1, [], 0),
    ("E-LAURA", "Laura", "Daniela", "Cardona", "Rendón", ["P-IND"], IND_B, ["H-CAL"], 1),
    ("E-EMILIO", "Emilio", "José", "Bedoya", "Zapata", ["P-IND"], IND_B, ["H-CAL"], 1),
    ("E-ANTONIA", "Antonia", "", "Marín", "Rúa", ["P-IND"], IND_B, ["H-CAL"], 1),
    ("E-JUANJOSE", "Juan", "José", "Correa", "Patiño", ["P-TDS"], TDS_A, [], 1),
    ("E-DANIELA", "Daniela", "Alejandra", "Ríos", "Gaviria", ["P-TDS"], TDS_A, [], 1),
    ("E-KEVIN", "Kevin", "Andrés", "Londoño", "Ruiz", ["P-TDS"], TDS_A, [], 1),
    ("E-MANUELA", "Manuela", "", "Sierra", "Ospina", ["P-TDS"], TDS_B, ["H-FPR"], 1),
    ("E-CRISTIAN", "Cristian", "Camilo", "Valencia", "Ríos", ["P-TDS"], TDS_B, ["H-FPR"], 1),
    ("E-YULIANA", "Yuliana", "", "Mesa", "Cano", ["P-TDS"], TDS_B, ["H-FPR"], 1),
    ("E-SOFIA", "Sofía", "", "Ramírez", "Botero", ["P-ADM"], ADM_A, [], 1),
    ("E-NICOLAS", "Nicolás", "", "Gutiérrez", "Álvarez", ["P-ADM"], ADM_A, [], 1),
    ("E-GABRIELA", "Gabriela", "", "Hoyos", "Franco", ["P-ADM"], ADM_A, [], 1),
    ("E-ALEJANDRO", "Alejandro", "", "Pineda", "Serna", ["P-ADM"], ADM_B, ["H-FAD"], 1),
    ("E-CAMILA", "Camila", "Andrea", "Villa", "Restrepo", ["P-ADM", "P-CON"], ADM_B + ["CTB-1"], ["H-FAD"], 1),
    ("E-DAVID", "David", "Esteban", "Orozco", "Toro", ["P-ADM", "P-CON"], ADM_B + ["CTB-1"], ["H-FAD"], 1),
    ("E-LUISA", "Luisa", "Fernanda", "Zuluaga", "Mejía", ["P-CON"], CON_A, [], 1),
    ("E-BRAYAN", "Brayan", "Stiven", "Muñoz", "Arias", ["P-CON"], CON_A, [], 1),
    ("E-CATALINA", "Catalina", "", "Ospina", "Jaramillo", ["P-CON"], CON_A, [], 1),
    ("E-JUANESTEBAN", "Juan", "Esteban", "Ruiz", "Cardona", ["P-CON"], CON_B, ["H-CTB"], 1),
    ("E-MELISSA", "Melissa", "", "Gallo", "Henao", ["P-CON"], CON_B, ["H-CTB"], 1),
    ("E-SEBASTIAN", "Sebastián", "Darío", "Rincón", "Vargas", ["P-CON"], CON_B, ["H-CTB"], 1),
    ("E-VALERIA", "Valeria", "", "Agudelo", "Restrepo", ["P-PSI"], PSI_A, [], 1),
    ("E-MARTIN", "Martín", "Elías", "Franco", "Gil", ["P-PSI"], PSI_A, [], 1),
    ("E-JULIANA", "Juliana", "", "Arbeláez", "Posada", ["P-PSI"], PSI_A, [], 1),
    ("E-SIMON", "Simón", "Darío", "Pérez", "Lozano", ["P-PSI"], PSI_B, ["H-PSD"], 1),
    ("E-ALEJANDRA", "Alejandra", "", "Vélez", "Marín", ["P-PSI"], PSI_B, ["H-PSD"], 1),
    ("E-MIGUEL", "Miguel", "Ángel", "Rojas", "Castaño", ["P-PSI"], [], [], 1),  # recien admitido, sin grupos
    ("E-JHON", "Jhon", "Fredy", "Salazar", "Ocampo", ["P-ESP"], ESP, [], 1),
    ("E-MARCELA", "Marcela", "Patricia", "Duque", "Arango", ["P-ESP"], ESP, [], 1),
    ("E-HERNANDO", "Hernando", "José", "Cifuentes", "Mora", ["P-ESP"], ESP, [], 1),
    ("E-LORENA", "Lorena", "Isabel", "Taborda", "Ríos", ["P-ESP"], ESP, [], 0),
]

# Asistencia: % de faltas sin justa causa por matricula (resto: 0-8 % segun hash) y excusas
TASAS = {
    ("E-SANTIAGO", "BDA-1"): (28, 0), ("E-BRAYAN", "ETI-2"): (25, 0), ("E-KEVIN", "CAL-3"): (30, 0),   # perdida
    ("E-MATEO", "CAL-1"): (17, 0), ("E-LAURA", "IOP-1"): (16, 0), ("E-CAMILA", "COS-1"): (18, 0),     # riesgo
    ("E-VALERIA", "PSD-1"): (16, 0),
    ("E-CARLOS", "ARQ-1"): (4, 1), ("E-SARA", "CAL-2"): (4, 1), ("E-DANIELA", "FPR-1"): (0, 2),        # excusas
    ("E-ALEJANDRO", "H-FAD"): (25, 0),                                                                # 2026-1: CI al cierre
}
# Faltas forzadas en la ultima sesion registrada (para radicar reclamos dentro del plazo)
RECLAMOS = [  # (estudiante, grupo, categoria, justificacion, desenlace, docente que resuelve)
    ("E-MARIANA", "PRG-2", "CAL", "Mi abuela fue hospitalizada de urgencia y tuve que acompañarla.", "PENDIENTE", None),
    ("E-TOMAS", "CAL-1", "FMA", "Hubo cierre de la vía Rionegro–Marinilla por un derrumbe y no pude llegar.", "APROBADA", "T-GLO"),
    ("E-SOFIA", "FAD-1", "OTR", "Me quedé dormida porque trabajé hasta tarde.", "RECHAZADA", "T-BEA"),
    ("E-JULIANA", "ETI-1", "OTR", "Tuve un problema de transporte.", "RETIRADA", None),
    ("E-JUANJOSE", "FPR-1", "FMA", "Se presentó un corte de energía en el sector durante la sesión.", "PENDIENTE", None),
    ("E-LUISA", "CTB-1", "CAL", "Fallecimiento de un familiar cercano.", "PENDIENTE", None),
]
SIN_REGISTRO = ["GCA-1", "MER-1"]  # su ultima sesion vencida queda sin toma (cumplimiento del docente < 100 %)


def build():
    personas = {}  # clave -> dict

    def persona(clave, n1, n2, a1, a2, roles, **extra):
        canon = CANON.get(clave, {})
        uid = canon.get("uid") or gid("usuario", clave)
        correo = canon.get("correo") or f"{ascii_low(n1)}.{ascii_low(a1)}@uco.edu.co"
        p = dict(clave=clave, n1=n1, n2=n2 or "", a1=a1, a2=a2 or "", uid=uid, correo=correo,
                 username=canon.get("username") or correo.split("@")[0], roles=list(roles),
                 numero=canon.get("numero"), confirmado=1, activo=True)
        p.update(extra)
        personas[clave] = p
        return p

    for c, n1, n2, a1, a2 in ADMIN:
        persona(c, n1, n2, a1, a2, ["ADMINISTRADOR"])
    for c, n1, n2, a1, a2, fac in DECANOS:
        persona(c, n1, n2, a1, a2, ["DECANO"], facultad=fac)
    for c, n1, n2, a1, a2, fac, activo in COORDINADORES:
        persona(c, n1, n2, a1, a2, ["COORDINADOR"], facultad=fac, activo=activo)
    for c, n1, n2, a1, a2, _ in DOCENTES:
        if c == "T-DIA":
            personas["C-TDS"]["roles"].append("DOCENTE")
            personas["T-DIA"] = personas["C-TDS"]
        else:
            persona(c, n1, n2, a1, a2, ["DOCENTE"])
    for c, n1, n2, a1, a2, progs, g2, g1, conf in ESTUDIANTES:
        persona(c, n1, n2, a1, a2, ["ESTUDIANTE"], programas=progs, grupos=g2 + g1, confirmado=conf)

    unicos = {id(p): p for p in personas.values()}.values()
    correos = [p["correo"] for p in unicos]
    assert len(correos) == len(set(correos)), "correos duplicados"
    numero = 1036100000
    for p in sorted(unicos, key=lambda x: x["clave"]):
        if p["numero"] is None:
            numero += 7
            p["numero"] = numero
    return personas, list(unicos)


def rid(clave, kind):
    canon = CANON.get(clave)
    if canon and kind == canon_kind(clave):
        return canon["rid"]
    return gid(kind, clave)


def canon_kind(clave):
    return {"ADMIN": "administrador", "D-ING": "decano", "C-SIS": "coordinador", "T-MAR": "docente",
            "E-CARLOS": "estudiante", "E-ANA": "estudiante"}.get(clave)


def validar_horarios(personas):
    grupos = {g[0]: g for g in GRUPOS}

    def choca(a, b):
        return a[0] == b[0] and a[1] < b[2] and b[1] < a[2]

    def franjas(clave):
        g = grupos[clave]
        return [(d, i, f, g[4]) for d, i, f in g[5]]

    for dk, *_ in DOCENTES:
        mios = [k for k, g in grupos.items() if g[3] == dk]
        fr = [(k, x) for k in mios for x in franjas(k)]
        for i, (ka, a) in enumerate(fr):
            for kb, b in fr[i + 1:]:
                if ka != kb and a[3] == b[3] and choca(a, b):
                    raise SystemExit(f"cruce docente {dk}: {ka} vs {kb}")
    for c, *_rest in ESTUDIANTES:
        gs = personas[c]["grupos"]
        fr = [(k, x) for k in gs for x in franjas(k)]
        for i, (ka, a) in enumerate(fr):
            for kb, b in fr[i + 1:]:
                if ka != kb and a[3] == b[3] and choca(a, b):
                    raise SystemExit(f"cruce estudiante {c}: {ka} vs {kb}")


def values(rows):
    return ",\n".join("    (" + ", ".join(r) + ")" for r in rows)


def insert(table, cols, rows, key="id"):
    if not rows:
        return ""
    alias = ", ".join(cols)
    sel = ", ".join(f"v.{c}" for c in cols)
    return (f"INSERT INTO dbo.[{table}] ({alias})\nSELECT {sel}\nFROM (VALUES\n{values(rows)}\n) AS v ({alias})\n"
            f"WHERE NOT EXISTS (SELECT 1 FROM dbo.[{table}] t WHERE t.{key} = v.{key});\n\n")


def g(u):
    return f"CAST('{u}' AS UNIQUEIDENTIFIER)"


def main():
    personas, unicos = build()
    validar_horarios(personas)
    fac_id = {k: (i or gid("facultad", k)) for k, i, _ in FACULTADES}
    prog = {p[0]: p for p in PROGRAMAS}
    prog_id = {p[0]: (p[1] or gid("programa", p[0])) for p in PROGRAMAS}
    plan_id = {p[0]: (p[9] or gid("plan", p[0])) for p in PROGRAMAS}
    area_id = {c: (i or gid("area", c)) for c, _, i in AREAS}
    asig_id = {a[0]: ASIG_ID.get(a[0]) or gid("asignatura", a[0]) for a in ASIGNATURAS}
    per_id = {p[0]: (p[1] or gid("periodo", p[0])) for p in PERIODOS}
    grupo_id = {x[0]: GRUPO_ID.get(x[0]) or gid("grupo", x[0]) for x in GRUPOS}
    asig_nombre = {a[0]: a[1] for a in ASIGNATURAS}

    out = []
    w = out.append
    w("-- 01_estructura.sql  (GENERADO por generar_datos_prueba.py; no editar a mano)\n")
    w("USE [gestionasistenciadb];\nSET ANSI_NULLS ON;\nSET QUOTED_IDENTIFIER ON;\nSET NOCOUNT ON;\nSET XACT_ABORT ON;\n\n")
    w("IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo <> 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D')\n"
      "    OR (SELECT COUNT(*) FROM dbo.Usuario) > 80\n"
      "    THROW 50001, N'La base no parece recien desplegada: los datos de prueba se cargan sobre deploy_schema limpio.', 1;\n\n")
    w("BEGIN TRANSACTION;\n\n")
    w("-- Catalogos por codigo\n")
    w("DECLARE @tiCC UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');\n")
    w("DECLARE @egA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');\n\n")

    # Limpieza de la demo de las semillas 12-14 (grupo ARQ reutilizado; admin duplicado retirado)
    w("-- Limpieza de la demo de las semillas (sesiones y matriculas del grupo ARQ; segundo administrador)\n")
    w("DECLARE @gArq UNIQUEIDENTIFIER = 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D';\n")
    w("DELETE da FROM dbo.DetalleAsistencia da JOIN dbo.Asistencia a ON a.id = da.asistencia JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE a FROM dbo.Asistencia a JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE t FROM dbo.TokenAsistenciaToma t JOIN dbo.TomaAsistencia ta ON ta.id = t.toma JOIN dbo.Sesion s ON s.id = ta.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE ta FROM dbo.TomaAsistencia ta JOIN dbo.Sesion s ON s.id = ta.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE sc FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE ss FROM dbo.SesionSolicitud ss JOIN dbo.Sesion s ON s.id = ss.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE af FROM dbo.AvisoFaltaSesion af JOIN dbo.Sesion s ON s.id = af.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE ast FROM dbo.AvisoSesionSinToma ast JOIN dbo.Sesion s ON s.id = ast.sesion WHERE s.grupo = @gArq;\n")
    w("DELETE FROM dbo.Sesion WHERE grupo = @gArq;\nDELETE FROM dbo.Horario WHERE grupo = @gArq;\n")
    w("DELETE FROM dbo.EstudianteGrupo WHERE grupo = @gArq;\n")
    w("DELETE FROM dbo.Administrador WHERE id = 'F1A2B3C4-0000-0000-0000-000000000006';\n")
    w("DELETE FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000006'\n"
      "  AND NOT EXISTS (SELECT 1 FROM dbo.Administrador WHERE usuario = 'E1F2A3B4-0000-0000-0000-000000000006');\n\n")

    # Usuarios
    w("-- Usuarios (73). La contrasena real vive en Keycloak; la columna guarda el mismo marcador que las semillas.\n")
    for p in unicos:
        if p["clave"] in CANON:
            w(f"UPDATE dbo.Usuario SET primerNombre = {q(p['n1'])}, segundoNombre = {q(p['n2'])}, primerApellido = {q(p['a1'])}, "
              f"segundoApellido = {q(p['a2'])}, correoConfirmado = {p['confirmado']}, estado = 1 WHERE id = '{p['uid']}';\n")
    rows = [[g(p["uid"]), "@tiCC", str(p["numero"]), q(p["a1"]), q(p["a2"]), q(p["n1"]), q(p["n2"]), q(p["correo"]),
             str(p["confirmado"]), "1" if p["activo"] else "0", q(PASSWORD_PLACEHOLDER)]
            for p in unicos if p["clave"] not in CANON]
    w("\n" + insert("Usuario", ["id", "tipoIdIdentificacion", "numeroIdentificacion", "primerApellido", "segundoApellido",
                               "primerNombre", "segundoNombre", "correo", "correoConfirmado", "estado", "password"], rows))

    # Areas, facultades, decanos
    w(insert("Area", ["id", "nombre", "codigo", "estado"], [[g(area_id[c]), q(n), q(c), "1"] for c, n, _ in AREAS]))
    w(insert("Decano", ["id", "usuario", "estado"],
             [[g(rid(c, "decano")), g(personas[c]["uid"]), "1"] for c, *_ in DECANOS if c not in CANON]))
    w("UPDATE dbo.Facultad SET nombre = N'Facultad de Ingeniería' WHERE id = 'A2B3C4D5-0000-0000-0000-000000000001';\n\n")
    dec_de = {d[5]: d[0] for d in DECANOS if d[5]}
    w(insert("Facultad", ["id", "nombre", "institucion", "decano", "estado"],
             [[g(fac_id[k]), q(n), g(INSTITUCION), g(rid(dec_de[k], "decano")), "1"] for k, _, n in FACULTADES]))

    # Coordinadores (con facultad), programas
    w(insert("Coordinador", ["id", "usuario", "estado", "facultad"],
             [[g(rid(c, "coordinador")), g(personas[c]["uid"]), "1" if act else "0", g(fac_id[f])]
              for c, _, _, _, _, f, act in COORDINADORES if c not in CANON]))
    w("UPDATE dbo.Coordinador SET facultad = 'A2B3C4D5-0000-0000-0000-000000000001', estado = 1 WHERE id = 'F1A2B3C4-0000-0000-0000-000000000002';\n\n")
    w(f"UPDATE dbo.Programa SET nombre = {q('Ingeniería de Sistemas')}, "
      "modalidad = (SELECT id FROM dbo.Modalidad WHERE codigo = 'PRE'), jornada = (SELECT id FROM dbo.Jornada WHERE codigo = 'DIU') "
      "WHERE id = 'B2C3D4E5-0000-0000-0000-000000000001';\n\n")
    prow = []
    for k, _, f, tipo, nombre, coord, mod, jor, _, _ in PROGRAMAS:
        prow.append([g(prog_id[k]), g(fac_id[f]), q(tipo), q(nombre), g(rid(coord, "coordinador")), "1", q(mod), q(jor)])
    w("INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada)\n"
      "SELECT v.id, v.facultad, tp.id, v.nombre, v.coordinador, v.estado, mo.id, jo.id\nFROM (VALUES\n" + values(prow) +
      "\n) AS v (id, facultad, tipo, nombre, coordinador, estado, modalidad, jornada)\n"
      "JOIN dbo.TipoPrograma tp ON tp.codigo = v.tipo JOIN dbo.Modalidad mo ON mo.codigo = v.modalidad JOIN dbo.Jornada jo ON jo.codigo = v.jornada\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.Programa t WHERE t.id = v.id);\n\n")

    # Planes y semestres (+ un plan 2018 inactivo de Sistemas)
    planes = [[g(plan_id[k]), g(prog_id[k]), "2024", "1"] for k in prog]
    planes.append([g(gid("plan", "P-SIS-2018")), g(prog_id["P-SIS"]), "2018", "0"])
    w(insert("PlanEstudio", ["id", "programa", "inp", "estado"], planes))
    spe = {}
    srows = []
    for p in PROGRAMAS:
        for s in range(1, p[8] + 1):
            sid = SPE_ID.get((p[0], s)) or gid("semestre", f"{p[0]}-{s}")
            spe[(p[0], s)] = sid
            srows.append([g(sid), g(plan_id[p[0]]), q(f"S{s}")])
    for s in range(1, 11):  # el plan 2018 (inactivo) conserva su estructura de 10 semestres, como un plan real reemplazado
        srows.append([g(gid("semestre", f"P-SIS-2018-{s}")), g(gid("plan", "P-SIS-2018")), q(f"S{s}")])
    w("INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre)\nSELECT v.id, v.planEstudio, se.id\nFROM (VALUES\n" +
      values(srows) + "\n) AS v (id, planEstudio, semestre)\nJOIN dbo.Semestre se ON se.codigo = v.semestre\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio t WHERE t.id = v.id);\n\n")

    # Asignaturas y su vinculo con los planes
    w("UPDATE dbo.Asignatura SET area = 'C1D2E3F4-0000-0000-0000-000000000001' WHERE id = 'E2F3A4B5-0000-0000-0000-000000000001';\n")
    arows = [[g(asig_id[c]), q(c), q(n), str(cr), g(area_id[ar]), q(co), "1"] for c, n, cr, ar, co, _ in ASIGNATURAS]
    w("INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado)\n"
      "SELECT v.id, v.codigo, v.nombre, v.credito, v.area, c.id, v.estado\nFROM (VALUES\n" + values(arows) +
      "\n) AS v (id, codigo, nombre, credito, area, componente, estado)\nJOIN dbo.Componente c ON c.codigo = v.componente\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.Asignatura t WHERE t.id = v.id);\n\n")
    w("UPDATE dbo.AsignaturaPlanEstudio SET fechaVinculacionUtc = '2025-12-01' WHERE id = 'E2F3A4B5-0001-0000-0000-000000000001';\n")
    aprows = []
    for c, _, _, _, _, links in ASIGNATURAS:
        for pk, s, car in links:
            aid = APE_ID.get((c, pk, s)) or gid("asignaturaplan", f"{c}-{pk}-{s}")
            aprows.append([g(aid), g(asig_id[c]), g(spe[(pk, s)]), q(car)])
    w("INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc)\n"
      "SELECT v.id, v.asignatura, v.spe, ca.id, 1, '2025-12-01'\nFROM (VALUES\n" + values(aprows) +
      "\n) AS v (id, asignatura, spe, caracter)\nJOIN dbo.CaracterAsignaturaPlan ca ON ca.codigo = v.caracter\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio t WHERE t.id = v.id);\n\n")

    # Docentes y vinculos con programas
    w(insert("Docente", ["id", "usuario"], [[g(rid(c, "docente")), g(personas[c]["uid"])] for c, *_ in DOCENTES if c not in CANON]))
    dprows = []
    for c, *_n, links in DOCENTES:
        for pk, tv, act in links:
            dprows.append([g(gid("docenteprograma", f"{c}-{pk}")), g(rid(c, "docente")), g(prog_id[pk]), q(tv), str(act)])
    w("INSERT INTO dbo.DocentePrograma (id, docente, programa, estado, fechaVinculacionUtc)\n"
      "SELECT v.id, v.docente, v.programa, v.estado, '2025-12-01'\nFROM (VALUES\n" + values(dprows) +
      "\n) AS v (id, docente, programa, tipo, estado)\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma t WHERE t.docente = v.docente AND t.programa = v.programa);\n\n")

    # Periodos
    w(insert("PeriodoAcademico", ["id", "institucion", "nombre", "codigo", "fechaInicio", "fechaFin", "anio"],
             [[g(per_id[k]), g(INSTITUCION), q(n), str(c), f"'{a}'", f"'{b}'", str(y)] for k, _, n, c, a, b, y in PERIODOS]))

    # Estudiantes, programas y matriculas
    w(insert("Estudiante", ["id", "usuario"],
             [[g(rid(c, "estudiante")), g(personas[c]["uid"])] for c, *_ in ESTUDIANTES if c not in CANON]))
    w("DELETE FROM dbo.EstudiantePrograma WHERE estudiante IN ('F1A2B3C4-0000-0000-0000-000000000004', 'F1A2B3C4-0000-0000-0000-000000000005');\n")
    eprows = [[g(gid("estudianteprograma", f"{c}-{pk}")), g(rid(c, "estudiante")), g(prog_id[pk])]
              for c, *_n, progs, _g2, _g1, _cf in ESTUDIANTES for pk in progs]
    w(insert("EstudiantePrograma", ["id", "estudiante", "programa"], eprows))
    inscritos = {}
    egrows = []
    for c, *_n, _p, g2, g1, _cf in ESTUDIANTES:
        for gk in g2 + g1:
            inscritos[gk] = inscritos.get(gk, 0) + 1
            egrows.append([g(gid("estudiantegrupo", f"{c}-{gk}")), "@egA", g(rid(c, "estudiante")), g(grupo_id[gk])])

    # Grupos y horarios
    grows = []
    for k, ac, cod, doc, per, _fr, cupo in GRUPOS:
        n = inscritos.get(k, 0)
        cupo = n if cupo == "LLENO" else (n + 1 if cupo == "CASI" else cupo)
        nombre = f"Grupo {cod:02d} - {asig_nombre[ac]}"[:50]
        grows.append([g(grupo_id[k]), g(asig_id[ac]), g(per_id[per]), str(cod), q(nombre), str(cupo), "0", "0", "0", g(rid(doc if doc != "T-DIA" else "T-DIA", "docente"))])
    w("UPDATE dbo.Grupo SET docente = 'F1A2B3C4-0000-0000-0000-000000000003' WHERE id = @gArq;\n")
    w(insert("Grupo", ["id", "asignatura", "periodoAcademico", "codigo", "nombre", "cantidadEstudiantes",
                       "cantidadEstudiantesFinalizaron", "cantidadEstudiantesCancelaronVoluntadPropia",
                       "cantidadEstudiantesCancelaronAutomaticamente", "docente"], grows))
    for r in grows:
        if r[0] == g(grupo_id["ARQ-1"]):
            w(f"UPDATE dbo.Grupo SET nombre = {r[4]}, cantidadEstudiantes = {r[5]} WHERE id = @gArq;\n\n")
    hrows = []
    for k, _a, _c, _d, _p, fr, _cu in GRUPOS:
        for i, (dia, a, b) in enumerate(fr):
            hi, hf = h(a, b)
            hrows.append([g(gid("horario", f"{k}-{i}")), g(grupo_id[k]), q(dia), f"'{hi:%H:%M}'", f"'{hf:%H:%M}'"])
    w("INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)\nSELECT v.id, v.grupo, d.id, CAST(v.hi AS TIME), CAST(v.hf AS TIME)\n"
      "FROM (VALUES\n" + values(hrows) + "\n) AS v (id, grupo, dia, hi, hf)\nJOIN dbo.Dia d ON d.codigo = v.dia\n"
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.Horario t WHERE t.id = v.id);\n\n")
    w(insert("EstudianteGrupo", ["id", "estado", "estudiante", "grupo"], egrows))

    # Festivos nacionales (fuente oficial que carga el backend; aqui se precargan para generar sesiones)
    fest = [l.split("|") for l in open(os.path.join(HERE, "festivos.txt"), encoding="utf-8-sig").read().splitlines()
            if l.strip() and not l.startswith("C|")]
    frows = [[g(gid("festivo", f[0])), f"'{f[0]}'", f[1], q(f[2]), q(f[3]), f[4]] for f in fest]
    w("INSERT INTO dbo.DiaFestivo (id, fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga)  -- anio es calculada\n"
      "SELECT v.id, v.fecha, v.nombre, v.fuente, v.activo, SYSUTCDATETIME(), NEWID()\nFROM (VALUES\n" + values(frows) +
      "\n) AS v (id, fecha, anio, nombre, fuente, activo)\nWHERE NOT EXISTS (SELECT 1 FROM dbo.DiaFestivo t WHERE t.fecha = v.fecha);\n\n")
    for anio in sorted({f[1] for f in fest}):
        tot = sum(1 for f in fest if f[1] == anio)
        w("IF NOT EXISTS (SELECT 1 FROM dbo.CargaDiaFestivo WHERE anio = %s)\n"
          "    INSERT INTO dbo.CargaDiaFestivo (id, anio, fuente, totalFestivos, festivosInsertados, festivosActualizados, "
          "festivosDesactivados, diferenciasCalculoLocal, usuarioEjecutor, fechaCargaUtc, idCorrelacion)\n"
          "    VALUES (NEWID(), %s, N'CALENDARIOS_NACIONALES', %d, %d, 0, 0, 0, NULL, SYSUTCDATETIME(), NEWID());\n" % (anio, anio, tot, tot))
    # Red del campus del LABORATORIO: con el backend en contenedor, las peticiones del navegador o de las pruebas llegan desde
    # la puerta de enlace de la red de Docker (p. ej. 192.168.80.1), no desde 127.0.0.1. Se agregan los rangos privados que usa
    # Docker (y la LAN de la casa, para probar el QR desde un celular). Solo para pruebas locales; en otro ambiente el
    # administrador lo define en Parametros (RED/CIDRS_CAMPUS) o en el Catalogo de Parametros.
    w("\nUPDATE dbo.CatalogoParametro SET valor = N'127.0.0.1/32,::1/128,172.16.0.0/12,192.168.0.0/16'\n"
      "WHERE grupo = N'RED' AND clave = N'CIDRS_CAMPUS';\n")
    w("\nCOMMIT TRANSACTION;\nPRINT N'01_estructura: OK';\n")
    open(os.path.join(HERE, "01_estructura.sql"), "w", encoding="utf-8").write("".join(out))

    # ── 02 sesiones ──
    s = ["-- 02_sesiones.sql  (GENERADO)\nUSE [gestionasistenciadb];\nSET ANSI_NULLS ON;\nSET QUOTED_IDENTIFIER ON;\nSET NOCOUNT ON;\n\n",
         f"DECLARE @p20262 UNIQUEIDENTIFIER = '{per_id['P20262']}', @p20261 UNIQUEIDENTIFIER = '{per_id['P20261']}';\n",
         "DECLARE @g UNIQUEIDENTIFIER, @u UNIQUEIDENTIFIER, @c UNIQUEIDENTIFIER;\n",
         "DECLARE @canc INT, @conAs INT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;\n\n",
         "-- 2026-2: generador real (horario -> sesiones, festivos nacen cancelados), ejecutado como el docente titular\n",
         "DECLARE cur CURSOR LOCAL FAST_FORWARD FOR\n  SELECT g.id, d.usuario FROM dbo.Grupo g JOIN dbo.Docente d ON d.id = g.docente\n"
         "  WHERE g.periodoAcademico = @p20262 AND NOT EXISTS (SELECT 1 FROM dbo.Sesion s WHERE s.grupo = g.id);\n",
         "OPEN cur; FETCH NEXT FROM cur INTO @g, @u;\nWHILE @@FETCH_STATUS = 0\nBEGIN\n    SET @c = NEWID();\n"
         "    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g, @idCorrelacion = @c, @idUsuarioEjecutor = @u;\n"
         "    FETCH NEXT FROM cur INTO @g, @u;\nEND\nCLOSE cur; DEALLOCATE cur;\n\n",
         "-- 2026-1 (periodo ya terminado: el generador lo rechaza): mismas reglas que el generador, luego festivos\n",
         "IF NOT EXISTS (SELECT 1 FROM dbo.Sesion s JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.periodoAcademico = @p20261)\nBEGIN\n",
         "    ;WITH f AS (SELECT CAST('2026-02-02' AS DATE) AS d UNION ALL SELECT DATEADD(DAY, 1, d) FROM f WHERE d < '2026-06-12')\n",
         "    SELECT g.id AS grupo, f.d, h.horaInicio, h.horaFin,\n"
         "           ini = DATEADD(HOUR, 5, DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), h.horaInicio), CAST(f.d AS DATETIME2(7)))),\n"
         "           fin = DATEADD(HOUR, 5, DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), h.horaFin), CAST(f.d AS DATETIME2(7))))\n"
         "    INTO #s1\n    FROM f JOIN dbo.Horario h ON 1 = 1 JOIN dbo.Grupo g ON g.id = h.grupo AND g.periodoAcademico = @p20261\n"
         "    JOIN dbo.Dia di ON di.id = h.dia\n"
         "    WHERE di.codigo = CHOOSE(DATEDIFF(DAY, '19000101', f.d) % 7 + 1, 'LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')\n"
         "    OPTION (MAXRECURSION 400);\n",
         "    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)\n"
         "    SELECT NEWID(), CONCAT(N'Sesión ', x.n), x.n, UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6)),\n"
         "           DATEDIFF(WEEK, '2026-02-02', x.d) + 1, x.grupo, x.ini, x.fin, N'UTC_GENERADOR'\n"
         "    FROM (SELECT *, n = ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY ini) FROM #s1) x;\n    DROP TABLE #s1;\nEND\n\n",
         "DECLARE cur2 CURSOR LOCAL FAST_FORWARD FOR\n  SELECT g.id, d.usuario FROM dbo.Grupo g JOIN dbo.Docente d ON d.id = g.docente WHERE g.periodoAcademico = @p20261;\n",
         "OPEN cur2; FETCH NEXT FROM cur2 INTO @g, @u;\nWHILE @@FETCH_STATUS = 0\nBEGIN\n    SET @c = NEWID();\n    BEGIN TRANSACTION;\n"
         "    EXEC dbo.usp_internal_aplicar_festivos_grupo @idGrupo = @g, @soloFuturas = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @u,\n"
         "         @sesionesCanceladas = @canc OUTPUT, @sesionesConAsistencia = @conAs OUTPUT,\n"
         "         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;\n"
         "    IF @ok = 1 COMMIT TRANSACTION; ELSE BEGIN ROLLBACK TRANSACTION; PRINT CONCAT(N'festivos 2026-1 fallo: ', @mt); END\n"
         "    FETCH NEXT FROM cur2 INTO @g, @u;\nEND\nCLOSE cur2; DEALLOCATE cur2;\n\n",
         "SELECT periodo = pa.nombre, grupos = COUNT(DISTINCT g.id), sesiones = COUNT(s.id),\n"
         "       canceladasFestivo = SUM(IIF(sc.sesion IS NULL, 0, 1))\nFROM dbo.Grupo g JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico\n"
         "LEFT JOIN dbo.Sesion s ON s.grupo = g.id LEFT JOIN dbo.SesionCancelacion sc ON sc.sesion = s.id GROUP BY pa.nombre;\n"]
    open(os.path.join(HERE, "02_sesiones.sql"), "w", encoding="utf-8").write("".join(s))

    # ── 03 asistencia ──
    tasas = []
    for c, *_n, _p, g2, g1, _cf in ESTUDIANTES:
        for gk in g2 + g1:
            pct, ex = TASAS.get((c, gk), (int(uuid.UUID(gid("tasa", f"{c}-{gk}"))) % 9, 0))
            forz = 1 if any(r[0] == c and r[1] == gk for r in RECLAMOS) else 0
            tasas.append([g(gid("estudiantegrupo", f"{c}-{gk}")), str(pct), str(ex), str(forz)])
    a = ["-- 03_asistencia.sql  (GENERADO)\nUSE [gestionasistenciadb];\nSET ANSI_NULLS ON;\nSET QUOTED_IDENTIFIER ON;\nSET NOCOUNT ON;\nSET XACT_ABORT ON;\n\n",
         "IF EXISTS (SELECT 1 FROM dbo.TomaAsistencia) THROW 50002, N'Ya hay tomas de asistencia: el historial no se vuelve a generar.', 1;\n\n",
         "DECLARE @corte DATETIME2(7) = SYSUTCDATETIME();\n",
         "DECLARE @rcAN UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'AN'),\n"
         "        @rcSJC UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC'),\n"
         "        @rcEX UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'EX'),\n"
         "        @mManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE codigo = 'MANUAL'),\n"
         "        @mQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE codigo = 'QR'),\n"
         "        @eCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE codigo = 'CERRADA');\n\n",
         "CREATE TABLE #tasa (eg UNIQUEIDENTIFIER PRIMARY KEY, pct INT, ex INT, forzada BIT);\n",
         "INSERT INTO #tasa (eg, pct, ex, forzada) VALUES\n" + values(tasas) + ";\n\n",
         "-- Sesiones vencidas y no canceladas; la ultima de algunos grupos queda sin registro (cumplimiento del docente)\n",
         "SELECT s.id, s.grupo, s.fechaHoraInicio, s.fechaHoraFin, g.docente,\n"
         "       rnDesc = ROW_NUMBER() OVER (PARTITION BY s.grupo ORDER BY s.fechaHoraInicio DESC)\nINTO #ses\n"
         "FROM dbo.Sesion s JOIN dbo.Grupo g ON g.id = s.grupo\n"
         "WHERE s.fechaHoraFin < @corte AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id);\n",
         "DELETE FROM #ses WHERE rnDesc = 1 AND grupo IN (" + ", ".join(f"'{grupo_id[k]}'" for k in SIN_REGISTRO) + ");\n",
         ";WITH r AS (SELECT *, rn2 = ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY fechaHoraInicio DESC) FROM #ses) UPDATE r SET rnDesc = rn2;\n\n",
         "BEGIN TRANSACTION;\n",
         "SELECT idToma = NEWID(), s.id AS sesion, s.fechaHoraInicio, s.fechaHoraFin, s.docente, s.rnDesc,\n"
         "       esQr = IIF(ABS(CHECKSUM(s.id)) % 3 = 0, 1, 0)\nINTO #toma FROM #ses s;\n",
         "INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc,\n"
         "                                totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)\n"
         "SELECT t.idToma, t.sesion, 1, IIF(t.esQr = 1, @mQr, @mManual), @eCerrada, 0, t.docente, DATEADD(MINUTE, 5, t.fechaHoraInicio),\n"
         "       DATEADD(MINUTE, 20, t.fechaHoraInicio), 0, NEWID(), NEWID()\nFROM #toma t;\n\n",
         "SELECT idAsistencia = NEWID(), eg.id AS eg, t.idToma, t.sesion, t.fechaHoraInicio, t.fechaHoraFin, t.esQr,\n"
         "       forzar = IIF(ta.forzada = 1 AND t.rnDesc = 1, 1, 0), ta.pct, ta.ex,\n"
         "       n = COUNT(*) OVER (PARTITION BY eg.id)\nINTO #m\n"
         "FROM #toma t JOIN dbo.Sesion s ON s.id = t.sesion JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo JOIN #tasa ta ON ta.eg = eg.id;\n",
         "SELECT m.*, rn = ROW_NUMBER() OVER (PARTITION BY m.eg ORDER BY m.forzar DESC, ABS(CHECKSUM(m.eg, m.sesion))),\n"
         "       k = IIF(MAX(m.forzar) OVER (PARTITION BY m.eg) = 1 AND ROUND(m.pct * m.n / 100.0, 0) < 1, 1, CAST(ROUND(m.pct * m.n / 100.0, 0) AS INT))\n"
         "INTO #m2 FROM #m m;\n",
         "INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) SELECT idAsistencia, eg, sesion FROM #m2;\n",
         "DECLARE @base INT = (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);\n",
         "INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)\n"
         "SELECT NEWID(), @base + ROW_NUMBER() OVER (ORDER BY m.fechaHoraInicio, m.eg), m.idAsistencia,\n"
         "       IIF(m.rn <= m.k + m.ex, 0, 1),\n"
         "       CASE WHEN m.rn <= m.k THEN @rcSJC WHEN m.rn <= m.k + m.ex THEN @rcEX ELSE @rcAN END,\n"
         "       m.fechaHoraInicio, m.fechaHoraFin, m.idToma, IIF(m.esQr = 1 AND m.rn > m.k + m.ex, 1, 0), DATEADD(MINUTE, 20, m.fechaHoraInicio)\n"
         "FROM #m2 m;\n",
         "UPDATE ta SET totalAusentesMarcados = x.aus FROM dbo.TomaAsistencia ta\n"
         "JOIN (SELECT toma, aus = SUM(IIF(asistio = 0, 1, 0)) FROM dbo.DetalleAsistencia GROUP BY toma) x ON x.toma = ta.id;\n",
         "COMMIT TRANSACTION;\n\n",
         "SELECT tomas = (SELECT COUNT(*) FROM dbo.TomaAsistencia), asistencias = (SELECT COUNT(*) FROM dbo.Asistencia),\n"
         "       faltasSJC = (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE razonCausa = @rcSJC),\n"
         "       excusas = (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE razonCausa = @rcEX);\n"]
    open(os.path.join(HERE, "03_asistencia.sql"), "w", encoding="utf-8").write("".join(a))

    # ── 04 flujos ──
    def uid_of(k):
        return personas[k]["uid"]

    f = ["-- 04_flujos.sql  (GENERADO). Usa los SP reales con el ejecutor del rol que corresponde.\n"
         "USE [gestionasistenciadb];\nSET ANSI_NULLS ON;\nSET QUOTED_IDENTIFIER ON;\nSET NOCOUNT ON;\n\n",
         f"DECLARE @p20262 UNIQUEIDENTIFIER = '{per_id['P20262']}';\n",
         "DECLARE @g UNIQUEIDENTIFIER, @c UNIQUEIDENTIFIER, @rev UNIQUEIDENTIFIER, @sol UNIQUEIDENTIFIER, @ses UNIQUEIDENTIFIER, @toma UNIQUEIDENTIFIER;\n\n",
         "-- 1. Alertas de inasistencia (riesgo 15 %, perdida 20 %) de cada grupo de 2026-2\n",
         "DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id FROM dbo.Grupo WHERE periodoAcademico = @p20262;\n",
         "OPEN cur; FETCH NEXT FROM cur INTO @g;\nWHILE @@FETCH_STATUS = 0\nBEGIN\n    SET @c = NEWID();\n"
         "    EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @g, @idCorrelacion = @c;\n"
         "    FETCH NEXT FROM cur INTO @g;\nEND\nCLOSE cur; DEALLOCATE cur;\n\n"]

    def rev_de(est, gk):
        return (f"SELECT @rev = rc.id FROM dbo.RevisionCancelacion rc WHERE rc.estudianteGrupo = '{gid('estudiantegrupo', f'{est}-{gk}')}';\n")

    f.append("-- 2. Revisiones de cancelacion: Santiago (BDA-1) propuesta por el docente, pendiente del coordinador de Sistemas;\n"
             "--    Kevin (CAL-3) propuesta y aprobada por la coordinadora de Tec. Software (queda cancelado por inasistencia);\n"
             "--    Brayan (ETI-2) queda pendiente de la decision del docente.\n")
    f.append("SET @rev = NULL;\n" + rev_de("E-SANTIAGO", "BDA-1") +
             f"IF @rev IS NOT NULL BEGIN SET @c = NEWID(); EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev, @codigoDecision = N'PROPONER', "
             f"@motivo = N'Supera el 20 % de inasistencia sin justificación y no respondió a las alertas.', @idCorrelacion = @c, "
             f"@idUsuarioEjecutor = '{uid_of('T-FEL')}'; END ELSE PRINT N'Sin revision para Santiago';\n")
    f.append("SET @rev = NULL;\n" + rev_de("E-KEVIN", "CAL-3") +
             f"IF @rev IS NOT NULL BEGIN SET @c = NEWID(); EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev, @codigoDecision = N'PROPONER', "
             f"@motivo = N'Inasistencia del 30 % sin justificación.', @idCorrelacion = @c, @idUsuarioEjecutor = '{uid_of('T-GLO')}';\n"
             f"    SET @c = NEWID(); EXEC dbo.usp_resolver_revision_cancelacion @idRevision = @rev, @codigoDecision = N'APROBAR', "
             f"@motivo = N'Se confirma la cancelación por inasistencia según el reglamento.', @idCorrelacion = @c, "
             f"@idUsuarioEjecutor = '{uid_of('C-TDS')}'; END ELSE PRINT N'Sin revision para Kevin';\n\n")

    f.append("-- 3. Retiro de un estudiante por el docente (Isabella, Algebra Lineal)\nSET @c = NEWID();\n"
             f"EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = '{grupo_id['ALG-1']}', @idEstudiante = '{rid('E-ISABELLA', 'estudiante')}', "
             f"@motivo = N'La estudiante solicitó el retiro de la asignatura por cruce con su práctica laboral.', @idCorrelacion = @c, "
             f"@idUsuarioEjecutor = '{uid_of('T-FEL')}';\n\n")

    f.append("-- 4. Reclamos de asistencia radicados por los estudiantes sobre su ultima falta (dentro del plazo)\n")
    for est, gk, cat, just, fin, doc in RECLAMOS:
        eg = gid("estudiantegrupo", f"{est}-{gk}")
        f.append(f"SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id\n"
                 f"  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion\n"
                 f"  WHERE a.estudianteGrupo = '{eg}' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;\n"
                 f"SET @c = NEWID();\nEXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = '{rid(est, 'estudiante')}', @idSesion = @ses, "
                 f"@idToma = @toma, @categoria = N'{cat}', @justificacion = {q(just)}, @idsArchivoSoporte = NULL, @idCorrelacion = @c, "
                 f"@idUsuarioEjecutor = '{uid_of(est)}';\n"
                 f"SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = '{eg}');\n")
        if fin in ("APROBADA", "RECHAZADA"):
            resp = ("Se valida el soporte del cierre vial reportado." if fin == "APROBADA"
                    else "El motivo no corresponde a una justa causa según el reglamento.")
            f.append(f"SET @c = NEWID();\nEXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = '{rid(doc, 'docente')}', "
                     f"@accion = N'{fin}', @respuestaDocente = {q(resp)}, @idCorrelacion = @c, @idUsuarioEjecutor = '{uid_of(doc)}';\n")
        elif fin == "RETIRADA":
            f.append(f"SET @c = NEWID();\nEXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @sol, @idCorrelacion = @c, "
                     f"@idUsuarioEjecutor = '{uid_of(est)}';\n")
        f.append("\n")

    f.append("-- 5. Solicitudes de sesion extraordinaria creadas por docentes (pendientes del coordinador)\n"
             f"SET @c = NEWID();\nEXEC dbo.usp_crear_sesion_v2 @idGrupo = '{grupo_id['PRG-1']}', @nombre = N'Taller de refuerzo de ciclos', "
             f"@fechaHoraInicio = '2026-11-21T13:00:00', @fechaHoraFin = '2026-11-21T15:00:00', @idCorrelacion = @c, @idUsuarioEjecutor = '{uid_of('T-MAR')}';\n"
             f"SET @c = NEWID();\nEXEC dbo.usp_crear_sesion_v2 @idGrupo = '{grupo_id['CAL-3']}', @nombre = N'Repaso para el examen final', "
             f"@fechaHoraInicio = '2026-11-20T23:00:00', @fechaHoraFin = '2026-11-21T01:00:00', @idCorrelacion = @c, @idUsuarioEjecutor = '{uid_of('T-GLO')}';\n\n")
    f.append("SELECT alertas = (SELECT COUNT(*) FROM dbo.AlertaInasistencia), revisiones = (SELECT COUNT(*) FROM dbo.RevisionCancelacion),\n"
             "       reclamos = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia), solicitudesSesion = (SELECT COUNT(*) FROM dbo.SesionSolicitud);\n")
    open(os.path.join(HERE, "04_flujos.sql"), "w", encoding="utf-8").write("".join(f))

    # ── usuarios para Seguridad y directorio ──
    usuarios = []
    for p in unicos:
        usuarios.append(dict(username=p["username"], email=p["correo"], firstName=" ".join(x for x in (p["n1"], p["n2"]) if x),
                             lastName=" ".join(x for x in (p["a1"], p["a2"]) if x), idUsuario=p["uid"].lower(),
                             roles=p["roles"], enabled=p["activo"]))
    json.dump(dict(version=1, usuarios=usuarios), open(os.path.join(HERE, "usuarios_datos_prueba.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    prog_nombre = {p[0]: p[4] for p in PROGRAMAS}
    fac_nombre = {k: n for k, _, n in FACULTADES}
    md = ["# Usuarios de los datos de prueba\n\n",
          "Generado por `generar_datos_prueba.py`. Todos usan la contraseña común de laboratorio de `AGENTS.md` (sección 7); "
          "aquí no se escribe. Se entra por correo o por usuario en `http://localhost:4200`.\n\n"]

    def nombre(p):
        return " ".join(x for x in (p["n1"], p["n2"], p["a1"], p["a2"]) if x)

    md.append("## Administrador\n\n| Nombre | Correo | Usuario |\n|---|---|---|\n")
    md.append(f"| {nombre(personas['ADMIN'])} | {personas['ADMIN']['correo']} | {personas['ADMIN']['username']} |\n\n")
    md.append("## Decanos\n\n| Nombre | Correo | Facultad |\n|---|---|---|\n")
    for c, *_n, fac in DECANOS:
        md.append(f"| {nombre(personas[c])} | {personas[c]['correo']} | {fac_nombre.get(fac, 'Sin facultad (reemplazo)')} |\n")
    coord_prog = {p[5]: p[4] for p in PROGRAMAS}
    md.append("\n## Coordinadores\n\n| Nombre | Correo | Programa | Estado |\n|---|---|---|---|\n")
    for c, *_n, fac, act in COORDINADORES:
        md.append(f"| {nombre(personas[c])} | {personas[c]['correo']} | {coord_prog.get(c, 'Sin programa (' + fac_nombre[fac] + ')')} | "
                  f"{'Activo' if act else 'Inactivo'} |\n")
    md.append("\n## Docentes\n\n| Nombre | Correo | Grupos 2026-2 | Vínculos |\n|---|---|---|---|\n")
    for c, *_n, links in DOCENTES:
        gs = [f"{asig_nombre[x[1]]} G{x[2]}" for x in GRUPOS if x[3] == c and x[4] == "P20262"]
        vs = [f"{prog_nombre[pk]} ({tv}{'' if act else ', inactivo'})" for pk, tv, act in links]
        md.append(f"| {nombre(personas[c])} | {personas[c]['correo']} | {', '.join(gs) or 'Sin grupos'} | {'; '.join(vs)} |\n")
    md.append("\n## Estudiantes\n\n| Nombre | Correo | Programa(s) | Grupos 2026-2 |\n|---|---|---|---|\n")
    for c, *_n, progs, g2, _g1, conf in ESTUDIANTES:
        nota = "" if conf else " (correo sin verificar)"
        md.append(f"| {nombre(personas[c])}{nota} | {personas[c]['correo']} | {', '.join(prog_nombre[p] for p in progs)} | "
                  f"{', '.join(asig_nombre[next(x[1] for x in GRUPOS if x[0] == k)] for k in g2) or 'Sin grupos'} |\n")
    open(os.path.join(HERE, "USUARIOS.md"), "w", encoding="utf-8").write("".join(md))
    roles = {}
    for p in unicos:
        for r in p["roles"]:
            roles[r] = roles.get(r, 0) + 1
    print(json.dumps(dict(usuarios=len(unicos), roles=roles, grupos=len(GRUPOS), matriculas=len(egrows)), ensure_ascii=False))


if __name__ == "__main__":
    main()
