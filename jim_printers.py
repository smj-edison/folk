class JimObjPrinter:
    def __init__(self, val):
        self.val = val
        self.type_name = self.obj_type_name(val)

    def obj_type_name(self, obj):
        type_name = 'corrupted'
        
        try:
            type_name = obj['typePtr'].dereference()['name'].string()
        except Exception:
            pass

        if str(obj['typePtr']) == '0x0':
            type_name = 'none'

        return type_name


    def to_string(self):
        ref_count = self.val['refCount']
        header = f"Jim_Obj @ {self.val.address}, refCount: {ref_count}, type: {self.type_name}"

        string_repr = None
        match self.type_name:
            case "dict-substitution":
                string_repr = self.val['internalRep']['dictSubstValue']
            case "interpolated":
                string_repr = self.val['internalRep']['dictSubstValue']
            case "string":
                string_repr = self.val['bytes']
            case "compared-string":
                pass
            case "source":
                string_repr = self.val['bytes']
            case "scriptline":
                string_repr = self.val['internalRep']['scriptLineValue']
            case "script":
                string_repr = self.val['bytes']
            case "command":
                string_repr = self.val['bytes']
            case "variable":
                string_repr = self.val['bytes']
            case "int":
                string_repr = str(self.val['internalRep']['intValue'])
            case "coerced-double":
                string_repr = str(self.val['internalRep']['wideValue'])
            case "double":
                string_repr = str(self.val['internalRep']['doubleValue'])
            case "list":
                string_repr = self.val['bytes']
            case "dict":
                string_repr = self.val['bytes']
            case "index":
                string_repr = str(self.val['internalRep']['intValue'])
            case "return-code":
                string_repr = str(self.val['internalRep']['wideValue'])
            case "expression":
                string_repr = self.val['bytes']
            case "scanformatstring":
                string_repr = self.val['bytes']
            case "get-enum":
                string_repr = self.val['bytes']
            case "dict-substitution":
                string_repr = self.val['bytes']
            case "interpolated":
                string_repr = self.val['bytes']
            case "compared-string":
                string_repr = self.val['bytes']

        if string_repr:
            # The pointer is not NULL, so we can display it as a string.
            return f"{header} -> '{string_repr.string()[:100]}'"
        else:
            return f"{header} -> NULL"
    
    def children(self):
        length = None
        elements_ptr = None
        
        if self.type_name == 'list':
            length = int(self.val['internalRep']['listValue']['len'])
            elements_ptr = self.val['internalRep']['listValue']['ele']
        elif self.type_name == 'dict':
            length = int(self.val['internalRep']['dictValue']['len'])
            elements_ptr = self.val['internalRep']['dictValue']['table']

        print(elements_ptr)
        print(length)
        
        if length == None or elements_ptr == None:
            return
        
        for i in range(length):
            # The 'name' is the index, the 'value' is the element
            name = f'[{i}]'
            # elements_ptr[i] is a Jim_Obj*, so we dereference it
            value = elements_ptr[i].dereference()
            yield name, value

    def display_hint(self):
        if self.type_name == 'list':
            return 'array'

        if self.type_name == 'dict':
            return 'map'

        return 'string'


def jim_obj_lookup_function(val):
    """
    The lookup function to register our printer with GDB.
    """
    # Look for the type 'Jim_Obj'. The '.tag' attribute holds the bare struct name.
    if str(val.type) == 'Jim_Obj':
        return JimObjPrinter(val)
    return None

# Register the lookup function with GDB's pretty-printer framework.
gdb.pretty_printers.append(jim_obj_lookup_function)

print("loaded script")
