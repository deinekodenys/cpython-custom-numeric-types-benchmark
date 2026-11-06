/*
 * probe.c - minimal representatives of the architectural classes.
 *
 * Two extension types share the same stub arithmetic (a single addition of
 * doubles) and differ only in where the per-value state is kept:
 *
 *   InObj    state stored in the object, next to the value
 *   TblObj   state stored in an external table keyed by object address
 *
 * The file is compiled twice:
 *
 *   default      full C API             module probe_full     classes 3 and 5
 *   -DLIMITED    limited API (3.12)     module probe_limited  classes 4 and 7
 *
 * Both builds compile the same source lines. They differ only in how the
 * C API headers expand some operations: with Py_LIMITED_API set to 3.12 or
 * later, Py_INCREF() and Py_DECREF() become calls into the interpreter
 * instead of inline reference count updates.
 */

#ifdef LIMITED
#  define Py_LIMITED_API 0x030C0000
#endif

#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <stdint.h>

#ifdef LIMITED
#  define MODULE_NAME "probe_limited"
#  define MODULE_INIT PyInit_probe_limited
#else
#  define MODULE_NAME "probe_full"
#  define MODULE_INIT PyInit_probe_full
#endif


/* InObj: state stored in the object ------------------------------------- */

typedef struct {
    PyObject_HEAD
    double value;
    int mode;               /* per-value state, read on every operation */
} InObj;

static PyTypeObject *InObjType = NULL;

static PyObject *
inobj_new_value(double value, int mode)
{
    InObj *obj = PyObject_New(InObj, InObjType);
    if (obj == NULL) {
        return NULL;
    }
    obj->value = value;
    obj->mode = mode;
    return (PyObject *)obj;
}

static PyObject *
inobj_add(PyObject *a, PyObject *b)
{
    if (Py_TYPE(a) != InObjType || Py_TYPE(b) != InObjType) {
        Py_RETURN_NOTIMPLEMENTED;
    }
    const InObj *x = (const InObj *)a;
    const InObj *y = (const InObj *)b;
    return inobj_new_value(x->value + y->value, x->mode | y->mode);
}

static PyObject *
inobj_tp_new(PyTypeObject *type, PyObject *args, PyObject *kwds)
{
    static char *kwlist[] = {"value", NULL};
    double value;

    if (!PyArg_ParseTupleAndKeywords(args, kwds, "d", kwlist, &value)) {
        return NULL;
    }
    InObj *obj = PyObject_New(InObj, type);
    if (obj == NULL) {
        return NULL;
    }
    obj->value = value;
    obj->mode = 0;
    return (PyObject *)obj;
}

static void
inobj_dealloc(PyObject *self)
{
    PyTypeObject *type = Py_TYPE(self);

    PyObject_Free(self);
    /* Instances of heap types own a reference to their type. */
    Py_DECREF((PyObject *)type);
}

static PyObject *
inobj_float(PyObject *self)
{
    return PyFloat_FromDouble(((const InObj *)self)->value);
}

static PyType_Slot inobj_slots[] = {
    {Py_tp_doc, (void *)"Value with its state stored in the object."},
    {Py_tp_new, inobj_tp_new},
    {Py_tp_dealloc, inobj_dealloc},
    {Py_nb_add, inobj_add},
    {Py_nb_float, inobj_float},
    {0, NULL},
};

static PyType_Spec inobj_spec = {
    .name = MODULE_NAME ".InObj",
    .basicsize = sizeof(InObj),
    .itemsize = 0,
    .flags = Py_TPFLAGS_DEFAULT,
    .slots = inobj_slots,
};


/* TblObj: state stored in an external table ----------------------------- */

/*
 * Open addressing with linear probing, keyed by object address. This is the
 * cheapest faithful implementation of the class: a dict keyed by id() would
 * add a generic hash lookup through the C API to every access and overstate
 * the cost of external state.
 *
 * The table is far larger than the number of live keys (at most three while
 * a case is timed), so probing always terminates. Deletion clears the slot
 * without repairing the probe sequence, which is sufficient for this access
 * pattern; an operand whose entry cannot be found raises RuntimeError rather
 * than being measured silently.
 */

#define TABLE_BITS 16
#define TABLE_SIZE (1u << TABLE_BITS)
#define TABLE_MASK (TABLE_SIZE - 1u)

typedef struct {
    const void *key;
    double value;
    int mode;
} TableSlot;

static TableSlot table[TABLE_SIZE];

static inline unsigned int
table_hash(const void *key)
{
    uintptr_t x = (uintptr_t)key;
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    return (unsigned int)(x & TABLE_MASK);
}

static inline TableSlot *
table_find(const void *key)
{
    unsigned int i = table_hash(key);
    for (;;) {
        if (table[i].key == key) {
            return &table[i];
        }
        if (table[i].key == NULL) {
            return NULL;
        }
        i = (i + 1u) & TABLE_MASK;
    }
}

static inline void
table_put(const void *key, double value, int mode)
{
    unsigned int i = table_hash(key);
    while (table[i].key != NULL && table[i].key != key) {
        i = (i + 1u) & TABLE_MASK;
    }
    table[i].key = key;
    table[i].value = value;
    table[i].mode = mode;
}

static inline void
table_delete(const void *key)
{
    TableSlot *slot = table_find(key);
    if (slot != NULL) {
        slot->key = NULL;
    }
}

typedef struct {
    PyObject_HEAD           /* no per-value state in the object itself */
} TblObj;

static PyTypeObject *TblObjType = NULL;

static PyObject *
tblobj_add(PyObject *a, PyObject *b)
{
    if (Py_TYPE(a) != TblObjType || Py_TYPE(b) != TblObjType) {
        Py_RETURN_NOTIMPLEMENTED;
    }
    const TableSlot *sa = table_find(a);
    const TableSlot *sb = table_find(b);
    if (sa == NULL || sb == NULL) {
        PyErr_SetString(PyExc_RuntimeError, "operand state not found");
        return NULL;
    }
    TblObj *obj = PyObject_New(TblObj, TblObjType);
    if (obj == NULL) {
        return NULL;
    }
    table_put(obj, sa->value + sb->value, sa->mode | sb->mode);
    return (PyObject *)obj;
}

static PyObject *
tblobj_tp_new(PyTypeObject *type, PyObject *args, PyObject *kwds)
{
    static char *kwlist[] = {"value", NULL};
    double value;

    if (!PyArg_ParseTupleAndKeywords(args, kwds, "d", kwlist, &value)) {
        return NULL;
    }
    TblObj *obj = PyObject_New(TblObj, type);
    if (obj == NULL) {
        return NULL;
    }
    table_put(obj, value, 0);
    return (PyObject *)obj;
}

static void
tblobj_dealloc(PyObject *self)
{
    PyTypeObject *type = Py_TYPE(self);

    /* The allocator may reuse this address, so drop the entry first. */
    table_delete(self);
    PyObject_Free(self);
    /* Instances of heap types own a reference to their type. */
    Py_DECREF((PyObject *)type);
}

static PyObject *
tblobj_float(PyObject *self)
{
    const TableSlot *slot = table_find(self);
    if (slot == NULL) {
        PyErr_SetString(PyExc_RuntimeError, "object state not found");
        return NULL;
    }
    return PyFloat_FromDouble(slot->value);
}

static PyType_Slot tblobj_slots[] = {
    {Py_tp_doc, (void *)"Value with its state stored in an external table."},
    {Py_tp_new, tblobj_tp_new},
    {Py_tp_dealloc, tblobj_dealloc},
    {Py_nb_add, tblobj_add},
    {Py_nb_float, tblobj_float},
    {0, NULL},
};

static PyType_Spec tblobj_spec = {
    .name = MODULE_NAME ".TblObj",
    .basicsize = sizeof(TblObj),
    .itemsize = 0,
    .flags = Py_TPFLAGS_DEFAULT,
    .slots = tblobj_slots,
};


/* Module ----------------------------------------------------------------- */

static struct PyModuleDef module_def = {
    .m_base = PyModuleDef_HEAD_INIT,
    .m_name = MODULE_NAME,
    .m_doc = "Minimal class representatives for the cost measurement campaign.",
    .m_size = -1,           /* single-phase init: the state table is global */
};

PyMODINIT_FUNC
MODULE_INIT(void)
{
    PyObject *module = PyModule_Create(&module_def);
    if (module == NULL) {
        return NULL;
    }

    /* The type objects stay referenced by the statics for the lifetime of
       the process; the module holds its own references. */
    InObjType = (PyTypeObject *)PyType_FromSpec(&inobj_spec);
    if (InObjType == NULL
        || PyModule_AddObjectRef(module, "InObj", (PyObject *)InObjType) < 0) {
        goto error;
    }
    TblObjType = (PyTypeObject *)PyType_FromSpec(&tblobj_spec);
    if (TblObjType == NULL
        || PyModule_AddObjectRef(module, "TblObj", (PyObject *)TblObjType) < 0) {
        goto error;
    }
    return module;

error:
    Py_XDECREF((PyObject *)InObjType);
    InObjType = NULL;
    Py_XDECREF((PyObject *)TblObjType);
    TblObjType = NULL;
    Py_DECREF(module);
    return NULL;
}
