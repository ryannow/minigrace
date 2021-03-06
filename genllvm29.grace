import io
import sys
import ast
import util
import buildinfo
import subtype

// genllvm produces LLVM bitcode from the AST, and optionally links and
// compiles it to native code. Code that affects the way the compiler behaves
// is in the "compile" method at the bottom. Other methods principally deal
// with translating a single AST node to bitcode, and parallel the AST and
// parser.

var tmp
var verbosity := 30
var pad1 := 1
var auto_count := 0
var constants := []
var output := []
var usedvars := []
var declaredvars := []
var bblock := "entry"
var linenum := 1
var modules := []
var staticmodules := []
var values := []
var outfile
var modname := "main"
var runmode := "build"
var buildtype := "bc"
var gracelibPath := "gracelib.bc"
var inBlock := false
var paramsUsed := 1
var topLevelMethodPos := 1

method out(s) {
    output.push(s)
}
method outprint(s) {
    util.outprint(s)
}
method log_verbose(s) {
    util.log_verbose(s)
}
method beginblock(s) {
    bblock := "%" ++ s
    out(s ++ ":")
}
method compilearray(o) {
    var myc := auto_count
    auto_count := auto_count + 1
    var r
    out("  %array" ++ myc ++ " = call %object @alloc_List()")
    for (o.value) do {a ->
        r := compilenode(a)
        out("  store %object " ++ r ++ ", %object* %params_0")
        out("  call %object @callmethod(%object %array"
            ++ myc ++ ", i8* getelementptr([5 x i8]* @.str._push"
            ++ ",i32 0,i32 0), i32 1, %object* %params)")
    }
    o.register := "%array" ++ myc
}
method compilemember(o) {
    // Member in value position is actually a nullary method call.
    var l := []
    var c := ast.astcall(o, l)
    var r := compilenode(c)
    o.register := r
}
method compileobjouter(selfr) {
    var myc := auto_count
    auto_count := auto_count + 1
    var nm := "outer"
    var len := length(nm) + 1
    var enm := escapestring(nm)
    var con := "@.str.methname" ++ myc ++ " = private unnamed_addr "
        ++ "constant [" ++ len ++ " x i8] c\"" ++ enm ++ "\\00\""
    constants.push(con)
    out("; OBJECT OUTER DEC " ++ enm)
    out("  call void @adddatum2(%object {selfr}, %object %self, i32 0)")
    outprint("define private %object @\"reader_" ++ modname ++ "_" ++ enm ++ "_" ++ myc
        ++ "\"(%object %self, i32 %nparams, "
        ++ "%object* %args, i32 %flags) \{")
    outprint("  %uo = bitcast %object %self to %UserObject*")
    outprint("  %fieldpp = getelementptr %UserObject* %uo, i32 0, i32 3")
    outprint("  %fieldpf = getelementptr [0 x %object]* %fieldpp, i32 0, i32 0")
    outprint("  %val = load %object* %fieldpf")
    outprint("  ret %object %val")
    outprint("\}")
    out("  call void @addmethod2(%object " ++ selfr
        ++ ", i8* getelementptr(["
        ++ len ++ " x i8]* @.str.methname" ++ myc ++ ", i32 0, i32 0), "
        ++ "%object(%object, i32, %object*, i32)* "
        ++ "getelementptr(%object "
        ++ "(%object, i32, %object*, i32)* "
        ++ "@\"reader_" ++ modname ++ "_" ++ enm
        ++ "_" ++ myc
        ++ "\"))")
}
method compileobjdefdec(o, selfr, pos) {
    var val := "%undefined"
    if (false != o.value) then {
        val := compilenode(o.value)
    }
    var myc := auto_count
    auto_count := auto_count + 1
    var nm := o.name.value
    var len := length(nm) + 1
    var enm := escapestring(nm)
    var con := "@.str.methname" ++ myc ++ " = private unnamed_addr "
        ++ "constant [" ++ len ++ " x i8] c\"" ++ enm ++ "\\00\""
    constants.push(con)
    out("; OBJECT CONST DEC " ++ enm)
    out("  call void @adddatum2(%object {selfr}, %object {val}, i32 {pos})")
    outprint("define private %object @\"reader_" ++ modname ++ "_" ++ enm ++ "_" ++ myc
        ++ "\"(%object %self, i32 %nparams, "
        ++ "%object* %args, i32 %flags) \{")
    outprint("  %uo = bitcast %object %self to %UserObject*")
    outprint("  %fieldpp = getelementptr %UserObject* %uo, i32 0, i32 3")
    outprint("  %fieldpf = getelementptr [0 x %object]* %fieldpp, i32 0, i32 {pos}")
    outprint("  %val = load %object* %fieldpf")
    outprint("  ret %object %val")
    outprint("\}")
    out("  call void @addmethod2(%object " ++ selfr
        ++ ", i8* getelementptr(["
        ++ len ++ " x i8]* @.str.methname" ++ myc ++ ", i32 0, i32 0), "
        ++ "%object(%object, i32, %object*, i32)* "
        ++ "getelementptr(%object "
        ++ "(%object, i32, %object*, i32)* "
        ++ "@\"reader_" ++ modname ++ "_" ++ enm
        ++ "_" ++ myc
        ++ "\"))")
}
method compileobjvardec(o, selfr, pos) {
    var val := "%undefined"
    if (false != o.value) then {
        val := compilenode(o.value)
    }
    var myc := auto_count
    auto_count := auto_count + 1
    var nm := o.name.value
    var len := length(nm) + 1
    var enm := escapestring(nm)
    var con := "@.str.methname" ++ myc ++ " = private unnamed_addr "
        ++ "constant [" ++ len ++ " x i8] c\"" ++ enm ++ "\\00\""
    constants.push(con)
    out("; OBJECT VAR DEC " ++ nm)
    out("  call void @adddatum2(%object {selfr}, %object {val}, i32 {pos})")
    outprint("define private %object @\"reader_" ++ modname ++ "_" ++ enm ++ "_" ++ myc
        ++ "\"(%object %self, i32 %nparams, "
        ++ "%object* %args, i32 %flags) \{")
    outprint("  %uo = bitcast %object %self to %UserObject*")
    outprint("  %fieldpp = getelementptr %UserObject* %uo, i32 0, i32 3")
    outprint("  %fieldpf = getelementptr [0 x %object]* %fieldpp, i32 0, i32 {pos}")
    outprint("  %val = load %object* %fieldpf")
    outprint("  ret %object %val")
    outprint("\}")
    out("  call void @addmethod2(%object " ++ selfr
        ++ ", i8* getelementptr(["
        ++ len ++ " x i8]* @.str.methname" ++ myc ++ ", i32 0, i32 0), "
        ++ "%object(%object, i32, %object*, i32)* "
        ++ "getelementptr(%object "
        ++ "(%object, i32, %object*, i32)* "
        ++ "@\"reader_" ++ modname ++ "_" ++ enm
        ++ "_" ++ myc
        ++ "\"))")
    var nmw := nm ++ ":="
    len := length(nmw) + 1
    nmw := escapestring(nmw)
    con := "@.str.methnamew" ++ myc ++ " = private unnamed_addr "
        ++ "constant [" ++ len ++ " x i8] c\"" ++ nmw ++ "\\00\""
    constants.push(con)
    outprint("define private %object @\"writer_" ++ modname ++ "_" ++ enm ++ "_" ++ myc
        ++ "\"(%object %self, i32 %nparams, "
        ++ "%object* %args, i32 %flags) \{")
    outprint("  %params = getelementptr %object* %args, i32 0")
    outprint("  %par0 = load %object* %params")
    outprint("  %uo = bitcast %object %self to %UserObject*")
    outprint("  %fieldpp = getelementptr %UserObject* %uo, i32 0, i32 3")
    outprint("  %fieldpf = getelementptr [0 x %object]* %fieldpp, i32 0, i32 {pos}")
    outprint("  store %object %par0, %object* %fieldpf")
    outprint("  %none = load %object* @none")
    outprint("  ret %object %none")
    outprint("\}")
    out("  call void @addmethod2(%object " ++ selfr
        ++ ", i8* getelementptr(["
        ++ len ++ " x i8]* @.str.methnamew" ++ myc ++ ", i32 0, i32 0), "
        ++ "%object(%object, i32, %object*, i32)* "
        ++ "getelementptr(%object "
        ++ "(%object, i32, %object*, i32)* "
        ++ "@\"writer_" ++ modname ++ "_" ++ enm
        ++ "_" ++ myc
        ++ "\"))")
}
method compileclass(o) {
    var params := o.params
    var mbody := [ast.astobject(o.value, o.superclass)]
    var newmeth := ast.astmethod(ast.astidentifier("new", false), params, mbody,
        false)
    var obody := [newmeth]
    var cobj := ast.astobject(obody, false)
    var con := ast.astdefdec(o.name, cobj, false)
    o.register := compilenode(con)
}
method compileobject(o) {
    var origInBlock := inBlock
    inBlock := false
    var myc := auto_count
    auto_count := auto_count + 1
    var selfr := "%obj" ++ myc
    var numFields := 1
    var numMethods := 0
    var pos := 1
    for (o.value) do { e ->
        if (e.kind == "vardec") then {
            numMethods := numMethods + 1
        }
        numMethods := numMethods + 1
        numFields := numFields + 1
    }
    if (numFields == 3) then {
        numFields := 4
    }
    if (o.superclass /= false) then {
        selfr := compilenode(o.superclass)
    } else {
        out("  " ++ selfr ++ " = call %object @alloc_obj2(i32 {numMethods},"
            ++ "i32 {numFields})")
    }
    compileobjouter(selfr)
    out("  call void @adddatum2(%object {selfr}, %object %self, i32 0)")
    for (o.value) do { e ->
        if (e.kind == "method") then {
            compilemethod(e, selfr, pos)
        }
        if (e.kind == "vardec") then {
            compileobjvardec(e, selfr, pos)
        }
        if (e.kind == "defdec") then {
            compileobjdefdec(e, selfr, pos)
        }
        pos := pos + 1
    }
    out("  call void @set_type(%object {selfr}, "
        ++ "i16 {subtype.typeId(o.otype)})")
    o.register := selfr
    inBlock := origInBlock
}
method compileblock(o) {
    def origInBlock = inBlock
    inBlock := true
    var myc := auto_count
    auto_count := auto_count + 1
    var applymeth := ast.astmethod(ast.astidentifier("apply", false),
        o.params, o.body, false)
    applymeth.selfclosure := true
    var objbody := ast.astobject([applymeth], false)
    var obj := compilenode(objbody)
    var modn := "Block<{modname}:{myc}>"
    var con := "@.str.block{myc} = private unnamed_addr "
        ++ "constant [{modn.size + 1} x i8] c\"{modn}\\00\""
    constants.push(con)
    out("  call void @setclassname(%object {obj}, "
        ++ "i8* getelementptr([{modn.size + 1} x i8]* @.str.block{myc},"
        ++ "i32 0,i32 0))")
    o.register := obj
    inBlock := origInBlock
}
method compilefor(o) {
    var myc := auto_count
    auto_count := auto_count + 1
    var over := compilenode(o.value)
    var blk := o.body
    var obj := compilenode(blk)
    out("  store %object " ++ over ++ ", %object* %params_0")
    out("  %iter" ++ myc ++ " = call %object @callmethod(%object " ++ over
        ++ ", i8* getelementptr([5 x i8]* @.str._iter"
        ++ ",i32 0,i32 0), i32 1, %object* %params)")
    
    out("  br label %BeginFor" ++ myc)
    beginblock("BeginFor" ++ myc)
    out("  %condobj" ++ myc ++ " = call %object @callmethod(%object %iter"
        ++ myc
        ++ ", i8* getelementptr([9 x i8]* @.str._havemore"
        ++ ",i32 0,i32 0), i32 1, %object* %params)")
    var creg := "%cond" ++ myc
    out("  " ++ creg ++ "_valp = call i1 @istrue(%object %condobj"
        ++ myc ++ ")")
    out("  " ++ creg ++ " = icmp eq i1 0, " ++ creg ++ "_valp")
    out("br i1 " ++ creg ++ ", label %EndFor" ++ myc
        ++ ", label %ForBody" ++ myc)
    beginblock("ForBody" ++ myc)
    var tret := "null"
    var tblock := "ERROR"
    out(" %forval" ++ myc ++ " = call %object @callmethod(%object %iter"
        ++ myc
        ++ ", i8* getelementptr([5 x i8]* @.str._next"
        ++ ",i32 0,i32 0), i32 0, %object* %params)")
    out("  store %object %forval" ++ myc ++ ", %object* %params_0")
    out("  call %object @callmethod(%object " ++ obj
        ++ ", i8* getelementptr([6 x i8]* @.str._apply"
        ++ ",i32 0,i32 0), i32 1, %object* %params)")
    tblock := bblock
    out("  br label %BeginFor" ++ myc)
    beginblock("EndFor" ++ myc)
    o.register := "%none" // "%while" ++ myc
}
method compilemethod(o, selfobj, pos) {
    // How to deal with closures:
    // Calculate body, find difference of usedvars/declaredvars, if closure
    // then build as such. At top of method body bind %var_x as usual, but
    // set to pointer from the additional closure parameter.
    var origParamsUsed := paramsUsed
    paramsUsed := 1
    var origInBlock := inBlock
    inBlock := o.selfclosure
    var oldout := output
    var oldbblock := bblock
    var oldusedvars := usedvars
    var olddeclaredvars := declaredvars
    output := []
    usedvars := []
    declaredvars := []
    var myc := auto_count
    auto_count := auto_count + 1
    var name := o.value.value
    var nm := name ++ myc
    beginblock("entry")
    output.pop
    var i := o.params.size
    if (o.varargs) then {
        var van := escapestring(o.vararg.value)
        out("  %\"var_init_" ++ van ++ "\" = call %object @process_varargs("
            ++ "%object* %args, i32 {i}, i32 %nparams)")
        out("  %\"var_" ++ van ++ "\" = call %object* @alloc_var()")
        out("  store %object %\"var_init_{van}\", %object* %\"var_{van}\"")
        declaredvars.push(van)
    }
    out("  %undefined = load %object* @undefined")
    out("  %none = load %object* @none")
    var ret := "%none"
    for (o.body) do { l ->
        if ((l.kind == "vardec") | (l.kind == "defdec")
            | (l.kind == "class")) then {
            var tnm := escapestring(l.name.value)
            declaredvars.push(tnm)
            out("  %\"var_{tnm}\" = call %object* @alloc_var()")
            out("  store %object %undefined, %object* %\"var_{tnm}\"")
        }
    }
    for (o.body) do { l ->
        ret := compilenode(l)
    }
    out("  ret %object " ++ ret)
    out("\}")
    var body := output
    output := []
    var closurevars := []
    for (usedvars) do { u ->
        var decl := false
        for (declaredvars) do { d->
            if (d == u) then {
                decl := true
            }
        }
        if (decl) then {
            decl := decl
        } else {
            var found := false
            for (closurevars) do { v ->
                if (v == u) then {
                    found := true
                }
            }
            if (found) then {
                found := found
            } else {
                closurevars.push(u)
            }
        }
    }
    if (o.selfclosure) then {
        closurevars.push("self")
    }
    var litname := "@\"meth_" ++ modname ++ "_" ++ escapestring(nm) ++ "\""
    outprint(";;;; METHOD DEFINITION: " ++ name)
    if (closurevars.size > 0) then {
        if (o.selfclosure) then {
            out("define private %object " ++ litname ++ "(%object %realself, i32 %nparams, "
                ++ "%object* %args, i32 %flags) \{")
            beginblock("closureinit")
            out("  %uo = bitcast %object %realself to %UserObject*")
        } else {
            out("define private %object " ++ litname ++ "(%object %self, i32 %nparams, "
                ++ "%object* %args, i32 %flags) \{")
            beginblock("closureinit")
            out("  %uo = bitcast %object %self to %UserObject*")
        }
        out("  %closurepp = getelementptr %UserObject* %uo, i32 0, i32 3")
        out("  %closurepf = getelementptr [0 x %object]* %closurepp, i32 0, i32 {pos}")
        out("  %closurepc = bitcast %object* %closurepf to %object***")
        out("  %closure = load %object*** %closurepc")
        out("  br label %entry")
    } else {
        out("define private %object " ++ litname ++ "(%object %self, i32 %nparams, "
            ++ "%object* %args, i32 %flags) \{")
    }
    beginblock("entry")
    // We need to detect which parameters are used in a closure, and
    // treat those specially. As params[] is stack-allocated, references
    // to those variables would fail once the method was out of scope
    // unless we copied them onto the heap.
    i := 0
    def toremove = []
    for (o.params) do { p ->
        var pn := escapestring(p.value)
        if (closurevars.contains(pn)) then {
            out("  %\"var_" ++ pn ++ "\" = call %object* @alloc_var()")
            out("  %argp_{i} = getelementptr %object* %args, i32 {i}")
            out("  %argval_{i} = load %object* %argp_{i}")
            out("  store %object %\"argval_{i}\", %object* %\"var_{pn}\"")
            toremove.push(pn)
        } else {
            out("  %\"var_" ++ pn ++ "\" = getelementptr %object* %args, "
                ++ "i32 " ++ i)
        }
        declaredvars.push(pn)
        i := i + 1
    }
    def origclosurevars = closurevars
    closurevars := []
    for (origclosurevars) do {pn->
        if (toremove.contains(pn)) then {
            // Remove this one
        } else {
            closurevars.push(pn)
        }
    }
    out("  %params = alloca %object, i32 " ++ paramsUsed)
    for (0..(paramsUsed-1)) do { ii ->
        out("  %params_" ++ ii ++ " = getelementptr %object* %params, i32 "
            ++ ii)
    }
    var j := 0
    for (closurevars) do { cv ->
        if (cv == "self") then {
            out("  %varc_" ++ cv ++ " = getelementptr %object** %closure, i32 " ++ j)
            out("  %self2 = load %object** %varc_" ++ cv)
            out("  %self = load %object* %self2")
        } else {
            out("  %\"varc_" ++ cv ++ "\" = getelementptr %object** %closure, i32 " ++ j)
            out("  %\"var_" ++ cv ++ "\" = load %object** %\"varc_" ++ cv
                ++ "\"")
        }
        j := j + 1
    }
    for (body) do { l->
        out(l)
    }
    out(";;;; ENDS")
    for (output) do {l ->
        outprint(l)
    }
    output := oldout
    bblock := oldbblock
    usedvars := oldusedvars
    declaredvars := olddeclaredvars
    for (closurevars) do { cv ->
        if (cv /= "self") then {
            if ((usedvars.contains(cv)).not) then {
                usedvars.push(cv)
            }
        }
    }
    var len := length(name) + 1
    var con := "@.str.methname" ++ myc ++ " = private unnamed_addr "
        ++ "constant [" ++ len ++ " x i8] c\"" ++ name ++ "\\00\""
    constants.push(con)
    if (closurevars.size == 0) then {
        out("  call void @addmethod2(%object " ++ selfobj
            ++ ", i8* getelementptr(["
            ++ len ++ " x i8]* @.str.methname" ++ myc ++ ", i32 0, i32 0), "
            ++ "%object(%object, i32, %object*, i32)* getelementptr(%object " 
            ++ "(%object, i32, %object*, i32)* " ++ litname ++ "))")
    } else {
        out("  call void @block_savedest(%object " ++ selfobj ++ ")")
        out("  %closure" ++ myc ++ " = call %object** @createclosure(i32 "
            ++ closurevars.size ++ ")")
        for (closurevars) do { v ->
            if (v == "self") then {
                out("  %selfpp" ++ auto_count ++ " = "
                    ++ "call %object* @alloc_var()")
                out("  store %object %self, %object* %selfpp" ++ auto_count)
                out("  call void @addtoclosure(%object** %closure" ++ myc ++ ", "
                    ++ "%object* %selfpp" ++ auto_count ++ ")")
                auto_count := auto_count + 1
            } else {
                out("  call void @addtoclosure(%object** %closure" ++ myc ++ ", "
                    ++ "%object* %\"var_" ++ v ++ "\")")
            }
        }
        var uo := "uo{myc}"
        out("  %{uo} = bitcast %object {selfobj} to %UserObject*")
        out("  %closurepp{myc} = getelementptr %UserObject* %{uo}, i32 0, i32 3")
        out("  %closurepf{myc} = getelementptr [0 x %object]* %closurepp{myc}, i32 0, i32 {pos}")
        out("  %closurepc{myc} = bitcast %object* %closurepf{myc} to %object***")
        out("  %closurec{myc} = bitcast %object** %closure{myc} to %object")
        out("  store %object %closurec{myc}, %object* %closurepf{myc}")
        out("  call void @addmethod2(%object " ++ selfobj
            ++ ", i8* getelementptr(["
            ++ len ++ " x i8]* @.str.methname" ++ myc ++ ", i32 0, i32 0), "
            ++ "%object(%object, i32, %object*, i32)* getelementptr(%object " 
            ++ "(%object, i32, %object*, i32)* " ++ litname ++ "))")
    }
    inBlock := origInBlock
    paramsUsed := origParamsUsed
}
method compilewhile(o) {
    var myc := auto_count
    auto_count := auto_count + 1
    out("  br label %BeginWhile" ++ myc)
    beginblock("BeginWhile" ++ myc)
    var cond := compilenode(o.value)
    var creg := "%cond" ++ myc
    out("  " ++ creg ++ "_valp = call i1 @istrue(%object "
        ++ cond ++ ")")
    out("  " ++ creg ++ " = icmp eq i1 0, " ++ creg ++ "_valp")
    out("br i1 " ++ creg ++ ", label %EndWhile" ++ myc
        ++ ", label %WhileBody" ++ myc)
    beginblock("WhileBody" ++ myc)
    var tret := "null"
    var tblock := "ERROR"
    for (o.body) do { l ->
        if ((l.kind == "vardec") | (l.kind == "defdec")
            | (l.kind == "class")) then {
            var tnm := escapestring(l.name.value)
            declaredvars.push(tnm)
            out("  %\"var_{tnm}\" = call %object* @alloc_var()")
            out("  store %object %undefined, %object* %\"var_{tnm}\"")
        }
    }
    for (o.body) do { l->
        tret := compilenode(l)
    }
    tblock := bblock
    out("  br label %BeginWhile" ++ myc)
    beginblock("EndWhile" ++ myc)
    //out("  %while" ++ myc ++ " = phi %object [ " ++ tret ++ ", "
    //    ++ tblock ++ "], [" ++ cond ++ ", %BeginIf" ++ myc ++ "]")
    o.register := cond // "%while" ++ myc
}
method compileif(o) {
    var myc := auto_count
    auto_count := auto_count + 1
    out("  br label %BeginIf" ++ myc)
    beginblock("BeginIf" ++ myc)
    var cond := compilenode(o.value)
    var creg := "%cond" ++ myc
    out("  " ++ creg ++ "_valp = call i1 @istrue(%object "
        ++ cond ++ ")")
    out("  " ++ creg ++ " = icmp eq i1 0, " ++ creg ++ "_valp")
    var startblock := bblock
    if (o.elseblock.size > 0) then {
        out("br i1 " ++ creg ++ ", label %FalseBranch" ++ myc
            ++ ", label %TrueBranch" ++ myc)
    } else {
        out("  %undefined" ++ myc ++ " = load %object* @undefined")
        out("br i1 " ++ creg ++ ", label %EndIf" ++ myc
            ++ ", label %TrueBranch" ++ myc)
    }
    beginblock("TrueBranch" ++ myc)
    var tret := "%none"
    var fret := "%none"
    var tblock := "ERROR"
    var fblock := "ERROR"
    for (o.thenblock) do { l ->
        if ((l.kind == "vardec") | (l.kind == "defdec")
            | (l.kind == "class")) then {
            var tnm := escapestring(l.name.value)
            declaredvars.push(tnm)
            out("  %\"var_{tnm}\" = call %object* @alloc_var()")
            out("  store %object %undefined, %object* %\"var_{tnm}\"")
        }
    }
    for (o.thenblock) do { l->
        tret := compilenode(l)
    }
    tblock := bblock
    out("  br label %EndIf" ++ myc)
    if (o.elseblock.size > 0) then {
        beginblock("FalseBranch" ++ myc)
        for (o.elseblock) do { l ->
            if ((l.kind == "vardec") | (l.kind == "defdec")
                | (l.kind == "class")) then {
                var tnm := escapestring(l.name.value)
                declaredvars.push(tnm)
                out("  %\"var_{tnm}\" = call %object* @alloc_var()")
                out("  store %object %undefined, %object* %\"var_{tnm}\"")
            }
        }
        for (o.elseblock) do { l->
            fret := compilenode(l)
        }
        out("  br label %EndIf" ++ myc)
        fblock := bblock
    }
    beginblock("EndIf" ++ myc)
    if (o.elseblock.size > 0) then {
        out("  %if" ++ myc ++ " = phi %object [ " ++ tret ++ ", "
            ++ tblock ++ "], [" ++ fret ++ ", " ++ fblock ++ "]")
    } else {
        out("  %if" ++ myc ++ " = phi %object [ " ++ tret ++ ", "
            ++ tblock ++ "], [%undefined" ++ myc ++ ", " ++ startblock ++ "]")
    }
    o.register := "%if" ++ myc
}
method compileidentifier(o) {
    var name := o.value
    if (name == "self") then {
        o.register := "%self"
    } elseif (name == "__compilerRevision") then {
        out("%str___compilerRevision" ++ auto_count
            ++ " = bitcast [41 x i8]* @.str._compilerRevision to i8*")
        out("%\"var_val___compilerRevision" ++ auto_count
            ++ "\" = call %object @alloc_String(i8* %str___compilerRevision"
            ++ auto_count ++ ")")
        o.register := "%\"var_val___compilerRevision" ++ auto_count ++ "\""
    } else {
        name := escapestring(name)
        if (modules.contains(name)) then {
            out("  %\"var_val_" ++ name ++ auto_count
                ++ "\" = load %object* @.module." ++ name)
        } else {
            usedvars.push(name)
            out("  %\"var_val_" ++ name ++ auto_count ++ "\" = load %object* "
                ++ "%\"var_" ++ name ++ "\"")
        }
        o.register := "%\"var_val_" ++ name ++ auto_count ++ "\""
        auto_count := auto_count + 1
    }
}
method compilebind(o) {
    var dest := o.dest
    var val := ""
    var c := ""
    var r := ""
    if (dest.kind == "identifier") then {
        val := o.value
        val := compilenode(val)
        var nm := escapestring(dest.value)
        usedvars.push(nm)
        out("  store %object " ++ val ++ ", %object* %\"var_" ++ nm ++ "\"")
        out("  %icmp{auto_count} = icmp eq %object {val}, %undefined")
        out("  br i1 %icmp{auto_count}, label %isundef{auto_count}, "
            ++ "label %isdef{auto_count}")
        beginblock("isundef{auto_count}")
        out("  call %object @callmethod(%object %none"
            ++ ", i8* getelementptr([11 x i8]* @.str._assignment"
            ++ ",i32 0,i32 0), i32 1, %object* %\"var_{nm}\")")
        out("  br label %isdef{auto_count}")
        beginblock("isdef{auto_count}")
        auto_count := auto_count + 1
        o.register := val
    } elseif (dest.kind == "member") then {
        out("; WARNING: non-local assigns not yet fully supported")
        dest.value := dest.value ++ ":="
        c := ast.astcall(dest, [o.value])
        r := compilenode(c)
        o.register := r
    } elseif (dest.kind == "index") then {
        var imem := ast.astmember("[]:=", dest.value)
        c := ast.astcall(imem, [dest.index, o.value])
        r := compilenode(c)
        o.register := r
    }
    o.register := "%none"
}
method compiledefdec(o) {
    var nm
    if (o.name.kind == "generic") then {
        nm := escapestring(o.name.value.value)
    } else {
        nm := escapestring(o.name.value)
    }
    declaredvars.push(nm)
    var val := o.value
    if (val) then {
        val := compilenode(val)
    } else {
        util.syntax_error("const must have value bound.")
    }
    out("  store %object " ++ val ++ ", %object* %\"var_"
        ++ nm ++ "\"")
    out("  %icmp{auto_count} = icmp eq %object {val}, %undefined")
    out("  br i1 %icmp{auto_count}, label %isundef{auto_count}, "
        ++ "label %isdef{auto_count}")
    beginblock("isundef{auto_count}")
    out("  call %object @callmethod(%object %none"
        ++ ", i8* getelementptr([11 x i8]* @.str._assignment"
        ++ ",i32 0,i32 0), i32 1, %object* %\"var_{nm}\")")
    out("  br label %isdef{auto_count}")
    beginblock("isdef{auto_count}")
    auto_count := auto_count + 1
    o.register := "%none"
}
method compilevardec(o) {
    var nm := escapestring(o.name.value)
    declaredvars.push(nm)
    var val := o.value
    var hadval := false
    if (val) then {
        val := compilenode(val)
        hadval := true
    } else {
        val := "%undefined"
    }
    out("  store %object " ++ val ++ ", %object* %\"var_"
        ++ nm ++ "\"")
    if (hadval) then {
        out("  %icmp{auto_count} = icmp eq %object {val}, %undefined")
        out("  br i1 %icmp{auto_count}, label %isundef{auto_count}, "
            ++ "label %isdef{auto_count}")
        beginblock("isundef{auto_count}")
        out("  call %object @callmethod(%object %none"
            ++ ", i8* getelementptr([11 x i8]* @.str._assignment"
            ++ ",i32 0,i32 0), i32 1, %object* %\"var_{nm}\")")
        out("  br label %isdef{auto_count}")
        beginblock("isdef{auto_count}")
        auto_count := auto_count + 1
    }
    o.register := "%none"
}
method compileindex(o) {
    var of := compilenode(o.value)
    var index := compilenode(o.index)
    out("  store %object " ++ index ++ ", %object* %params_0")
    out("  %idxres" ++ auto_count ++ " = call %object @callmethod(%object "
        ++ of ++ ", i8* getelementptr([3 x i8]* @.str._index"
        ++ ",i32 0,i32 0), i32 1, %object* %params)")
    o.register := "%idxres" ++ auto_count
    auto_count := auto_count + 1
}
method compileop(o) {
    var left := compilenode(o.left)
    var right := compilenode(o.right)
    auto_count := auto_count + 1
    if ((o.value == "+") | (o.value == "*") | (o.value == "/") |
        (o.value == "-") | (o.value == "%")) then {
        var rnm := "sum"
        var opnm := "plus"
        if (o.value == "*") then {
            rnm := "prod"
            opnm := "asterisk"
        }
        if (o.value == "/") then {
            rnm := "quotient"
            opnm := "slash"
        }
        if (o.value == "-") then {
            rnm := "diff"
            opnm := "minus"
        }
        if (o.value == "%") then {
            rnm := "modulus"
            opnm := "percent"
        }
        out("  store %object " ++ right ++ ", %object* %params_0")
        out("  %" ++ rnm ++ auto_count ++ " = call %object @callmethod(%object "
            ++ left ++ ", i8* getelementptr([2 x i8]* @.str._" ++ opnm
            ++ ",i32 0,i32 0), i32 1, %object* %params)")
        o.register := "%" ++ rnm ++ auto_count
        auto_count := auto_count + 1
    } else {
        var len := length(o.value) + 1
        var evl := escapestring(o.value)
        var con := "@.str" ++ constants.size ++ " = private unnamed_addr "
            ++ "constant [" ++ len ++ " x i8] c\"" ++ evl ++ "\\00\""
        out("  store %object " ++ right ++ ", %object* %params_0")
        out("  %opresult" ++ auto_count ++ " = call %object "
            ++ "@callmethod(%object " ++ left
            ++ ", i8* getelementptr([" ++ len ++ " x i8]* @.str"
            ++ constants.size ++ ",i32 0,i32 0), i32 1, %object* %params)")
        constants.push(con)
        o.register := "%opresult" ++ auto_count
        auto_count := auto_count + 1
    }
}
method compilecall(o) {
    var args := []
    var obj := ""
    var len := 0
    var con := ""
    var evl
    var i := 0
    for (o.with) do { p ->
        var r := compilenode(p)
        args.push(r)
    }
    if (args.size > paramsUsed) then {
        paramsUsed := args.size
    }
    evl := escapestring(o.value.value)
    if (o.value.kind == "member") then {
        obj := compilenode(o.value.in)
        len := length(o.value.value) + 1
        con := "@.str" ++ constants.size ++ " = private unnamed_addr "
            ++ "constant [" ++ len ++ " x i8] c\"" ++ evl ++ "\\00\""
        for (args) do { arg ->
            out("  store %object {arg}, %object* %params_{i}")
            i := i + 1
        }
        out("  %call" ++ auto_count ++ " = call %object "
            ++ "@callmethod(%object " ++ obj
            ++ ", i8* getelementptr([" ++ len ++ " x i8]* @.str"
            ++ constants.size ++ ",i32 0,i32 0), i32 "
            ++ args.size ++ ", %object* %params)")
        constants.push(con)
    } else {
        obj := "%self"
        len := length(o.value.value) + 1
        con := "@.str" ++ constants.size ++ " = private unnamed_addr "
            ++ "constant [" ++ len ++ " x i8] c\"" ++ evl ++ "\\00\""
        for (args) do { arg ->
            out("  store %object {arg}, %object* %params_{i}")
            i := i + 1
        }
        out("  %call" ++ auto_count ++ " = call %object "
            ++ "@callmethod(%object " ++ obj
            ++ ", i8* getelementptr([" ++ len ++ " x i8]* @.str"
            ++ constants.size ++ ",i32 0,i32 0), i32 "
            ++ args.size ++ ", %object* %params)")
        constants.push(con)
    }
    o.register := "%call" ++ auto_count
    auto_count := auto_count + 1
}
method compileoctets(o) {
    var escval := ""
    var l := length(o.value) / 2
    var i := 0
    for (o.value) do {c->
        if ((i % 2) == 0) then {
            escval := escval ++ "\\"
        }
        escval := escval ++ c
        i := i + 1
    }
    out("  %tmp" ++ auto_count ++ " = load %object* @.octlit"
        ++ auto_count)
    out("  %cmp" ++ auto_count ++ " = icmp ne %object %tmp"
        ++ auto_count ++ ", null")
    out("  br i1 %cmp" ++ auto_count ++ ", label %octlit"
        ++ auto_count ++ ".already, label %octlit"
        ++ auto_count ++ ".define")
    beginblock("octlit" ++ auto_count ++ ".already")
    out("  %alreadyoctets" ++ auto_count ++ " = load %object* @.octlit"
        ++ auto_count)
    out("  br label %octlit" ++ auto_count ++ ".end")
    beginblock("octlit" ++ auto_count ++ ".define")
    out("  %oct" ++ auto_count ++ " = getelementptr [" ++ l ++ " x i8]* @.oct" ++ constants.size ++ ", i32 0, i32 0")
    out("  %defoctets" ++ auto_count ++ " = call %object "
        ++ "@alloc_Octets(i8* "
          ++ "%oct" ++ auto_count ++ ", i32 " ++ l ++ ")")
    out("  store %object %defoctets" ++ auto_count ++ ", %object* "
        ++ "@.octlit" ++ auto_count)
    out("br label %octlit" ++ auto_count ++ ".end")
    beginblock("octlit" ++ auto_count ++ ".end")
    out(" %octets" ++ auto_count ++ " = phi %object [%alreadyoctets"
        ++ auto_count ++ ", %octlit" ++ auto_count ++ ".already], "
        ++ "[%defoctets" ++ auto_count ++ ", %octlit" ++ auto_count
        ++ ".define]")
    var con := "@.oct" ++ constants.size ++ " = private unnamed_addr "
        ++ "constant [" ++ l ++ " x i8] c\"" ++ escval ++ "\""
    constants.push(con)
    con := ("@.octlit" ++ auto_count
        ++ " = private global %object null")
    constants.push(con)
    o.register := "%octets" ++ auto_count
    auto_count := auto_count + 1
}
method compileimport(o) {
    out("; Import of " ++ o.value.value)
    var con
    var nm := escapestring(o.value.value)
    var modg := "@\".module." ++ nm ++ "\""
    var sblock := bblock
    out("  %tmp" ++ auto_count ++ " = load %object* " ++ modg)
    out("  %cmp" ++ auto_count ++ " = icmp ne %object %tmp" ++ auto_count
        ++ ", null")
    out("  br i1 %cmp" ++ auto_count ++ ", label %\"import." ++ nm
        ++ ".already\", label %\"import." ++ nm ++ ".define\"")
    beginblock("import." ++ nm ++ ".already")
    out("  %alreadymod" ++ auto_count ++ " = load %object* " ++ modg)
    out("  br label %\"import." ++ nm ++ ".end\"")
    beginblock("import." ++ nm ++ ".define")
    if (staticmodules.contains(nm)) then {
        out("  %\"tmp_mod_" ++ nm ++ "\" = call %object @module_"
            ++ nm ++ "_init()")
    } else {
        var mn := "@\".str.module." ++ nm ++ "\""
        var l := (nm.encode("utf-8")).size + 1
        con := mn ++ " = private unnamed_addr constant [" ++ l ++ " x i8] "
            ++ " c\"" ++ escapestring(nm) ++ "\\00\""
        constants.push(con)
        out("  %\"tmp_mod_" ++ nm ++ "\" = call %object @dlmodule(i8 *"
            ++ " getelementptr([" ++ l ++ " x i8]* " ++ mn ++ ",i32 0,i32 0))")
    }
    out("  store %object %\"tmp_mod_" ++ nm
        ++ "\", %object* @\".module." ++ nm ++ "\"")
    out("  store %object %\"tmp_mod_" ++ nm ++ "\", %object* @\".module."
        ++ nm ++ "\"")
    out("  br label %\"import." ++ nm ++ ".end\"")
    beginblock("import." ++ nm ++ ".end")
    out("  %\"tmp_modv_" ++ nm ++ "\" = phi %object [%alreadymod"
        ++ auto_count ++ ", %\"import." ++ nm ++ ".already\"], "
        ++ "[%\"tmp_mod_" ++ nm ++ "\", %\"import." ++ nm ++ ".define\"]")
    out("  %\"var_" ++ nm ++ "\" = call %object* @alloc_var()")
    out("  store %object %\"tmp_modv_" ++ nm
        ++ "\", %object* %\"var_" ++ nm ++ "\"")
    con := "@\".module." ++ nm ++ "\" = weak global %object null"
    modules.push(nm)
    constants.push(con)
    con := "declare %object @\"module_" ++ nm ++ "_init\"()"
    constants.push(con)
    auto_count := auto_count + 1
    o.register := "%none"
}
method compilereturn(o) {
    var reg := compilenode(o.value)
    if (inBlock) then {
        out("  call void @block_return(%object %realself, %object " ++ reg ++ ")")
    } else {
        out("  ret %object " ++ reg)
        beginblock("postret" ++ auto_count)
    }
    o.register := "%none"
}
method compilenum(o) {
    var cnum := o.value
    var havedot := false
    for (cnum) do {c->
        if (c == ".") then {
            havedot := true
        }
    }
    if (havedot.not) then {
        cnum := cnum ++ ".0"
    }
    out("  %num" ++ auto_count ++ " = call %object @alloc_Float64(double "
        ++ cnum ++ ")")
    o.register := "%num" ++ auto_count
    auto_count := auto_count + 1
}
method compilenode(o) {
    if (linenum /= o.line) then {
        linenum := o.line
        out("; Begin line " ++ linenum)
        out("  call void @setline(i32 " ++ linenum ++ ")")
    }
    if (o.kind == "num") then {
        compilenum(o)
    }
    var l := ""
    if (o.kind == "string") then {
        l := length(o.value)
        l := l + 1
        o.value := escapestring(o.value)
        out("  %tmp" ++ auto_count ++ " = load %object* @.strlit"
            ++ auto_count)
        out("  %cmp" ++ auto_count ++ " = icmp ne %object %tmp"
            ++ auto_count ++ ", null")
        out("  br i1 %cmp" ++ auto_count ++ ", label %strlit"
            ++ auto_count ++ ".already, label %strlit"
            ++ auto_count ++ ".define")
        beginblock("strlit" ++ auto_count ++ ".already")
        out("  %alreadystring" ++ auto_count ++ " = load %object* @.strlit"
            ++ auto_count)
        out("  br label %strlit" ++ auto_count ++ ".end")
        beginblock("strlit" ++ auto_count ++ ".define")
        out("  %str" ++ auto_count ++ " = getelementptr [" ++ l ++ " x i8]* @.str" ++ constants.size ++ ", i32 0, i32 0")
        out("  %defstring" ++ auto_count ++ " = call %object "
            ++ "@alloc_String(i8* "
              ++ "%str" ++ auto_count ++ ")")
        out("  store %object %defstring" ++ auto_count ++ ", %object* "
            ++ "@.strlit" ++ auto_count)
        out("br label %strlit" ++ auto_count ++ ".end")
        beginblock("strlit" ++ auto_count ++ ".end")
        out(" %string" ++ auto_count ++ " = phi %object [%alreadystring"
            ++ auto_count ++ ", %strlit" ++ auto_count ++ ".already], "
            ++ "[%defstring" ++ auto_count ++ ", %strlit" ++ auto_count
            ++ ".define]")
        var con := "@.str" ++ constants.size ++ " = private unnamed_addr "
            ++ "constant [" ++ l ++ " x i8] c\"" ++ o.value ++ "\\00\""
        constants.push(con)
        con := ("@.strlit" ++ auto_count
            ++ " = private global %object null")
        constants.push(con)
        o.register := "%string" ++ auto_count
        auto_count := auto_count + 1
    }
    if (o.kind == "index") then {
        compileindex(o)
    }
    if (o.kind == "octets") then {
        compileoctets(o)
    }
    if (o.kind == "import") then {
        compileimport(o)
    }
    if (o.kind == "return") then {
        compilereturn(o)
    }
    if (o.kind == "generic") then {
        o.register := compilenode(o.value)
    }
    if ((o.kind == "identifier")
        & ((o.value == "true") | (o.value == "false"))) then {
        var val := 0
        if (o.value == "true") then {
            val := 1
        }
        out("  %bool" ++ auto_count ++ " = call %object "
              ++ "@alloc_Boolean(i32 " ++ val ++ ")")
        o.register := "%bool" ++ auto_count
        auto_count := auto_count + 1
    } elseif (o.kind == "identifier") then {
        compileidentifier(o)
    }
    if (o.kind == "defdec") then {
        compiledefdec(o)
    }
    if (o.kind == "vardec") then {
        compilevardec(o)
    }
    if (o.kind == "block") then {
        compileblock(o)
    }
    if (o.kind == "method") then {
        compilemethod(o, "%self", topLevelMethodPos)
        topLevelMethodPos := topLevelMethodPos + 1
    }
    if (o.kind == "array") then {
        compilearray(o)
    }
    if (o.kind == "bind") then {
        compilebind(o)
    }
    if (o.kind == "while") then {
        compilewhile(o)
    }
    if (o.kind == "if") then {
        compileif(o)
    }
    if (o.kind == "class") then {
        compileclass(o)
    }
    if (o.kind == "object") then {
        compileobject(o)
    }
    if (o.kind == "member") then {
        compilemember(o)
    }
    if (o.kind == "for") then {
        compilefor(o)
    }
    if ((o.kind == "call")) then {
        if (o.value.value == "print") then {
            var args := []
            for (o.with) do { prm ->
                var r := compilenode(prm)
                args.push(r)
            }
            var parami := 0
            for (args) do { arg ->
                out("  store %object {arg}, %object* %params_{parami}")
                parami := parami + 1
            }
            out("  %call" ++ auto_count ++ " = call %object @gracelib_print(%object null, i32 "
                  ++ args.size ++ ", %object* %params)")
            o.register := "%call" ++ auto_count
            auto_count := auto_count + 1
        } elseif ((o.value.kind == "identifier")
                & (o.value.value == "length")) then {
            if (o.with.size == 0) then {
                out("; PP FOLLOWS")
                out(o.pretty(0))
                tmp := "null"
            } else {
                tmp := compilenode(o.with.first)
            }
            out("  %call" ++ auto_count ++ " = call %object "
                ++ "@gracelib_length(%object " ++ tmp ++ ")")
            o.register := "%call" ++ auto_count
            auto_count := auto_count + 1
        } elseif ((o.value.kind == "identifier")
                & (o.value.value == "escapestring")) then {
            tmp := o.with.first
            tmp := ast.astmember("_escape", tmp)
            tmp := ast.astcall(tmp, [])
            o.register := compilenode(tmp)
        } else {
            compilecall(o)
        }
    }
    if (o.kind == "op") then {
        compileop(o)
    }
    out("; compilenode returning " ++ o.register)
    o.register
}
method compile(vl, of, mn, rm, bt, glpath) {
    var argv := sys.argv
    var cmd
    values := vl
    outfile := of
    modname := mn
    runmode := rm
    buildtype := bt
    gracelibPath := glpath
    var linkfiles := []
    var ext := false
    if (runmode == "make") then {
        log_verbose("checking imports.")
        for (values) do { v ->
            if (v.kind == "import") then {
                var nm := v.value.value
                var exists := false
                if ((buildtype == "native") &
                    io.exists(nm ++ ".gso")) then {
                    exists := true
                }
                if (exists.not) then {
                    if (io.exists(nm ++ ".gco")) then {
                        if (io.newer(nm ++ ".gco", nm ++ ".grace")) then {
                            exists := true
                            linkfiles.push(nm ++ ".gco")
                            staticmodules.push(nm)
                        }
                    }
                }
                if (exists.not) then {
                    if (io.exists(nm ++ ".gc")) then {
                        ext := ".gc"
                    }
                    if (io.exists(nm ++ ".grace")) then {
                        ext := ".grace"
                    }
                    if (ext /= false) then {
                        cmd := argv.first ++ " --target llvm29"
                        cmd := cmd ++ " --make " ++ nm ++ ext
                        if (util.verbosity > 30) then {
                            cmd := cmd ++ " --verbose"
                        }
                        if (util.vtag) then {
                            cmd := cmd ++ " --vtag " ++ util.vtag
                        }
                        if (buildtype == "native") then {
                            cmd := cmd ++ " --native --noexec"
                        }
                        if (io.system(cmd).not) then {
                            util.syntax_error("failed processing import of " ++nm ++".")
                        }
                        exists := true
                        linkfiles.push(nm ++ ".gco")
                        staticmodules.push(nm)
                        ext := false
                    }
                }
                if ((nm == "sys") | (nm == "io")) then {
                    exists := true
                    staticmodules.push(nm)
                }
                if (exists.not) then {
                    util.syntax_error("failed finding import of " ++ nm ++ ".")
                }
            }
        }
    }
    out("@.str = private unnamed_addr constant [6 x i8] c\"Hello\\00\"")
    out("@.str._plus = private unnamed_addr constant [2 x i8] c\"+\\00\"")
    out("@.str._minus = private unnamed_addr constant [2 x i8] c\"-\\00\"")
    out("@.str._asterisk = private unnamed_addr constant [2 x i8] c\"*\\00\"")
    out("@.str._slash = private unnamed_addr constant [2 x i8] c\"/\\00\"")
    out("@.str._percent = private unnamed_addr constant [2 x i8] c\"%\\00\"")
    out("@.str._index = private unnamed_addr constant [3 x i8] c\"[]\\00\"")
    out("@.str._push = private unnamed_addr constant [5 x i8] c\"push\\00\"")
    out("@.str._iter = private unnamed_addr constant [5 x i8] c\"iter\\00\"")
    out("@.str._apply = private unnamed_addr constant [6 x i8] c\"apply\\00\"")
    out("@.str._havemore = private unnamed_addr constant [9 x i8] c\"havemore\\00\"")
    out("@.str._next = private unnamed_addr constant [5 x i8] c\"next\\00\"")
    out("@.str._assignment = private unnamed_addr constant [11 x i8] c\"assignment\\00\"")
    out("@.str.asString = private unnamed_addr constant [9 x i8] c\"asString\\00\"")
    out("@.str._compilerRevision = private unnamed_addr constant [41 x i8]"
        ++ "c\"" ++ buildinfo.gitrevision ++ "\\00\"")
    out("@undefined = private global %object null")
    out("@none = private global %object null")
    out("@argv = private global %object null")
    outprint("%Method = type \{i8*,i32,%object(%object,i32,%object*,i32)*\}")
    outprint("%ClassData = type \{ i8*, %Method*, i32 \}*")
    outprint("%object = type \{ i32, %ClassData, [0 x i8] \}*")
    outprint("%UserObject = type \{ i32, i8*, i8*, [0 x %object] \}")
    out("define %object @module_" ++ modname ++ "_init() \{")
    out("entry:")
    out("  %self = call %object @alloc_obj2(i32 100, i32 100)")
    var modn := "Module<{modname}>"
    var con := "@\".str._modcname_{modname}\" = private unnamed_addr "
        ++ "constant [{modn.size + 1} x i8] c\"{modn}\\00\""
    constants.push(con)
    out("  call void @setclassname(%object %self, "
        ++ "i8* getelementptr([{modn.size + 1} x i8]* "
        ++ "@\".str._modcname_{modname}\","
        ++ "i32 0,i32 0))")
    out("  %undefined = load %object* @undefined")
    out("  %none = load %object* @none")
    out("  %var_argv = call %object* @alloc_var()")
    out("  %tmp_argv = load %object* @argv")
    out("  store %object %tmp_argv, %object* %var_argv")
    out("  %var_HashMap = call %object* @alloc_var()")
    out("  %tmp_hmco = call %object @alloc_HashMapClassObject()")
    out("  store %object %tmp_hmco, %object* %var_HashMap")
    out("  %var_MatchFailed = call %object* @alloc_var()")
    out("  %tmp_mf = call %object @alloc_obj2(i32 0, i32 0)")
    out("  store %object %tmp_mf, %object* %var_MatchFailed")
    var tmpo := output
    output := []
    for (values) do { l ->
        if ((l.kind == "vardec") | (l.kind == "defdec")) then {
            var tnm := escapestring(l.name.value)
            declaredvars.push(tnm)
            out("  %\"var_{tnm}\" = call %object* @alloc_var()")
            out("  store %object %undefined, %object* %\"var_{tnm}\"")
        } elseif (l.kind == "class") then {
            var tnmc
            if (l.name.kind == "generic") then {
                tnmc := escapestring(l.name.value.value)
            } else {
                tnmc := escapestring(l.name.value)
            }
            declaredvars.push(tnmc)
            out("  %\"var_{tnmc}\" = call %object* @alloc_var()")
            out("  store %object %undefined, %object* %\"var_{tnmc}\"")
        }
    }
    for (values) do { o ->
        compilenode(o)
    }
    var tmpo2 := output
    output := tmpo
    out("  %params = alloca %object, i32 " ++ paramsUsed)
    for (0..(paramsUsed-1)) do { i ->
        out("  %params_" ++ i ++ " = getelementptr %object* %params, i32 " ++ i)
    }
    for (tmpo2) do { l->
        out(l)
    }
    paramsUsed := 1
    out("  ret %object %self")
    out("}")
    out("define weak i32 @main(i32 %argc, i8** %argv) \{")
    out("entry:")
    out("  call void @initprofiling()")
    if (util.extensions.contains("LogCallGraph")) then {
        var lcgfile := util.extensions.get("LogCallGraph")
        con := "@.str.logdest = private unnamed_addr "
            ++ "constant [{lcgfile.size + 1} x i8] c\"{lcgfile}\\00\""
        constants.push(con)
        out("  call void @enable_callgraph("
            ++ "i8* getelementptr([{lcgfile.size + 1} x i8]* "
            ++ "@.str.logdest,"
            ++ "i32 0,i32 0))")
    }
    out("  call void @gracelib_argv(i8** %argv)")
    out("  %params = alloca %object, i32 1")
    out("  %params_0 = getelementptr %object* %params, i32 0")
    out("  %undefined = call %object @alloc_Undefined()")
    out("  store %object %undefined, %object* @undefined")
    out("  %none = call %object @alloc_none()")
    out("  store %object %none, %object* @none")
    out("  %tmp_argv = call %object @alloc_List()")
    out("  %argv_i = alloca i32")
    out("  store i32 0, i32* %argv_i")
    out("  br label %argv.cond")
    beginblock("argv.cond")
    out("  %argv_tmp1 = load i32* %argv_i, align 4")
    out("  %argv_cmp = icmp slt i32 %argv_tmp1, %argc")
    out("  br i1 %argv_cmp, label %argv.body, label %argv.end")
    beginblock("argv.body")
    out("  %argv_iv = load i32* %argv_i")
    out("  %argv_idx = getelementptr i8** %argv, i32 %argv_iv")
    out("  %argv_val = load i8** %argv_idx")
    out("  %argv_tmp3 = call %object @alloc_String(i8* %argv_val)")
    out("  store %object %argv_tmp3, %object* %params_0")
    out("  call %object @callmethod(%object %tmp_argv, "
        ++ "i8* getelementptr([5 x i8]* @.str._push"
        ++ ",i32 0,i32 0), "
        ++ "i32 0, %object* %params)")
    out("  %argv_inc = add i32 %argv_iv, 1")
    out("  store i32 %argv_inc, i32* %argv_i")
    out("  br label %argv.cond")
    beginblock("argv.end")
    out("  call void @module_sys_init_argv(%object %tmp_argv)")
    out("  %var_argv = call %object* @alloc_var()")
    out("  store %object %tmp_argv, %object* %var_argv")
    out("  store %object %tmp_argv, %object* @argv")
    out("  call %object @module_" ++ modname ++ "_init()")
    out("  call void @gracelib_stats()")
    out("  ret i32 0")
    out("}")
    out("; constant definitions")
    for (constants) do { c ->
        out(c)
    }
    def mtx = subtype.boolMatrix
    out("@.subtypes = private unnamed_addr "
        ++ "constant [{mtx.size * mtx.size} x i1] [")
    var smfirst := true
    for (mtx) do {m1->
        for (m1) do {m2->
            if (smfirst) then {
                smfirst := false
            } else {
                out(",")
            }
            if (m2) then {
                out("i1 1")
            } else {
                out("i1 0")
            }
        }
    }
    out("]")
    out("@.typecount = private unnamed_addr constant i16 {mtx.size}")
    out("define private i1 @checksub(i16 %sub, i16 %sup) \{")
    out("entry:")
    out("  %tc = load i16* @.typecount")
    out("  %st = load [{mtx.size * mtx.size} x i1]* @.subtypes")
    out("  %ridx = mul i16 %sub, %tc")
    out("  %idx = add i16 %ridx, %sup")
    out("  %ptr = getelementptr [{mtx.size * mtx.size} x i1]* @.subtypes, i32 0, i16 %idx")
    out("  %rv = load i1* %ptr")
    out("  ret i1 %rv")
    out("}")
    out("; gracelib")
    out("declare %object @alloc_obj2(i32, i32)")
    out("declare void @addmethod2(%object, i8*, %object(%object, i32, %object*, i32)*)")
    out("declare void @adddatum2(%object, %object, i32)")
    out("declare %object @alloc_List()")
    out("declare %object @alloc_Float64(double)")
    out("declare %object @alloc_String(i8*)")
    out("declare %object @alloc_Octets(i8*, i32)")
    out("declare %object @alloc_Boolean(i32)")
    out("declare %object @alloc_Undefined()")
    out("declare %object @alloc_none()")
    out("declare %object @alloc_HashMapClassObject()")
    out("declare %object @callmethod(%object, i8*, i32, %object*)")
    out("declare %object @gracelib_print(%object, i32, %object*)")
    out("declare %object @gracelib_readall(%object, i32, %object*)")
    out("declare %object @gracelib_length(%object)")
    out("declare void @set_type(%object, i16)")
    out("declare void @setclassname(%object, i8*)")
    out("declare void @enable_callgraph(i8*)")
    out("declare %object @dlmodule(i8*)")
    out("declare %object* @alloc_var()")
    out("declare void @gracelib_argv(i8**)")
    out("declare void @module_sys_init_argv(%object)")
    out("declare i1 @istrue(%object)")
    out("declare void @gracelib_stats()")
    out("declare void @initprofiling()")
    out("declare %object** @createclosure(i32)")
    out("declare void @addtoclosure(%object**, %object*)")
    out("declare void @addclosuremethod(%object, i8*, %object(%object,")
    out("    i32, %object*, %object**)*, %object**)")
    out("declare void @setline(i32)")
    out("declare void @block_return(%object, %object)")
    out("declare void @block_savedest(%object)")
    out("declare %object @process_varargs(%object*, i32, i32)")
    out("; libc functions")
    out("declare i32 @puts(i8*)")
    out("declare i8* @malloc(i32)")
    log_verbose("writing file.")
    for (output) do { x ->
        outprint(x)
    }

    if (runmode == "make") then {
        outfile.close
        cmd := "llvm-as -o " ++ modname ++ ".gco " ++ modname ++ ".ll"
        if ((io.system(cmd)).not) then {
            io.error.write("Failed LLVM assembling")
            raise("Fatal.")
        }
        log_verbose("linking.")
        cmd := "llvm-link -o " ++ modname ++ ".bc "
        cmd := cmd ++ gracelibPath.replace(".o")with(".bc") ++ " "
        cmd := cmd ++ modname ++ ".gco"
        for (linkfiles) do { fn ->
            cmd := cmd ++ " " ++ fn
        }
        if ((io.system(cmd)).not) then {
            io.error.write("Failed LLVM linking")
            raise("Fatal.")
        }
        if ((buildtype == "native") & util.noexec.not) then {
            log_verbose("compiling to native.")
            cmd := "llc -o " ++ modname ++ ".s -relocation-model=pic " ++ modname
                ++ ".bc"
            if ((io.system(cmd)).not) then {
                io.error.write("failed native assembly compilation")
                raise("fatal.")
            }
            // Some systems (NetBSD) have dlsym() in libc and no libdl
            cmd := "ld -ldl -o /dev/null 2>/dev/null"
            if (io.system(cmd)) then {
                cmd := "gcc -fPIC -Wl,--export-dynamic -o " ++ modname ++ " -ldl "
                    ++ modname ++ ".s"
            } else {
                cmd := "gcc -fPIC -Wl,--export-dynamic -o " ++ modname ++ " "
                    ++ modname ++ ".s"
            }
            if ((io.system(cmd)).not) then {
                io.error.write("failed native assembly compilation")
                raise("fatal.")
            }
        }
        log_verbose("done.")
        if (buildtype == "run") then {
            cmd := "lli ./" ++ modname ++ ".bc"
            io.system(cmd)
        }
    }
}
