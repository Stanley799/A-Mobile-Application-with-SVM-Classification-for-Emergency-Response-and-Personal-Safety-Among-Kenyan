"""Tiny in-memory Firestore for tests: nested collections, ==, >=, <= filters, stream/get/set/create/update/delete/add."""
import datetime as dt
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import SERVER_TIMESTAMP

CLOCK = [1_000_000.0]


def now_dt():
    return dt.datetime.fromtimestamp(CLOCK[0], tz=dt.timezone.utc)


def fix(v):
    if v is SERVER_TIMESTAMP:
        return now_dt()
    if isinstance(v, dict):
        return {k: fix(x) for k, x in v.items()}
    return v


class Snap:
    def __init__(s, ref, d):
        s.reference, s.id, s._d = ref, ref.id, d

    @property
    def exists(s):
        return s._d is not None

    def to_dict(s):
        return dict(s._d) if s._d is not None else None


class Ref:
    def __init__(s, db, path):
        s.db, s.path, s.id = db, path, path.rsplit("/", 1)[-1]

    def get(s):
        return Snap(s, s.db.data.get(s.path))

    def set(s, d):
        s.db.data[s.path] = fix(dict(d))

    def create(s, d):
        if s.path in s.db.data:
            raise AlreadyExists("exists")
        s.set(d)

    def update(s, d):
        s.db.data[s.path].update(fix(dict(d)))

    def delete(s):
        s.db.data.pop(s.path, None)

    def collection(s, name):
        return Col(s.db, s.path + "/" + name)


class Query:
    def __init__(s, db, path, f=()):
        s.db, s.path, s.f = db, path, f

    def where(s, k, op, v):
        return Query(s.db, s.path, s.f + ((k, op, v),))

    def stream(s):
        pre = s.path + "/"
        for p, d in list(s.db.data.items()):
            if p.startswith(pre) and "/" not in p[len(pre):]:
                ok = True
                for k, op, v in s.f:
                    x = d.get(k)
                    ok = ok and ((x == v) if op == "==" else (x is not None and x >= v) if op == ">=" else (x is not None and x <= v))
                if ok:
                    yield Snap(Ref(s.db, p), d)


class Col(Query):
    def document(s, id):
        return Ref(s.db, s.path + "/" + id)

    def add(s, d):
        n = sum(1 for p in s.db.data if p.startswith(s.path + "/"))
        s.db.data[f"{s.path}/auto{n}"] = fix(dict(d))


class DB:
    def __init__(s):
        s.data = {}

    def collection(s, name):
        return Col(s, name)

    def put(s, path, d):
        s.data[path] = fix(dict(d))
