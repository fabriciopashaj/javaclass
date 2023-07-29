import binarylang
import streams, strutils

type
  ConstKind* {.pure.} = enum
    Utf8
    Integer
    Float
    Long
    Double
    Class
    String
    Fieldref
    Methodref
    InterfaceMethodref
    NameAndType
    MethodHandle
    MethodType
    Dynamic
    InvokeDynamic
    Module
    Package
    Unusable
  AccessFlag* {.pure.} = enum
    Public = 1
    Private
    Protected
    Static
    Final
    Super
    Volatile
    Transient
    Interface
    Abstract
    Synthetic
    Annotation
    Enum
    Module
  AccessFlags* = set[AccessFlag]
  RefKind* {.pure.} = enum
    GetField = 1
    GetStatic
    PutField
    PutStatic
    InvokeVirtual
    InvokeStatic
    InvokeSpecial
    NewInvokeSpecial
    InvokeInterface

proc toConstKind(v: uint8): ConstKind =
  if v in {1'u8, 3'u8..12'u8, 15'u8..20'u8}:
    result = ConstKind(v - 1'u8 - uint8(v > 1) - 2'u8 * uint8(v > 12))
  else:
    raise newException(ValueError, "Invalid constant tag: " & $v)

proc fromConstKind(kind: ConstKind): uint8 =
  uint8(kind) + 1 + uint8(kind > Utf8) + 2'u8 * uint8(kind > NameAndType)

struct(utf8Info):
  bu16: length
  s:    bytes(length.int)

struct(refInfo):
  bu16: classIndex
  bu16: nameAndTypeIndex

struct(nameAndTypeInfo):
  bu16: nameIndex
  bu16: descriptorIndex

struct(dynamicInfo):
  bu16: bootstrapMethodAttrIndex
  bu16: nameAndTypeIndex

template utf8Get(parse, parsed, output: untyped) =
  parse
  output = parsed.bytes
template utf8Put(encode, encoded, output: untyped) =
  output = Utf8Info(length: encoded.len.uint16, bytes: encoded)
  encode

union(constant, ConstKind):
  (Utf8):               *utf8Info {utf8[string]}: utf8
  (Integer):            bu32:                     integer
  (Float):              bf32:                     float
  (Long):               bu64:                     long
  (Double):             bf64:                     double
  (Module,
   Package,
   Class,
   String):             bu16:                     short
  (Fieldref,
   Methodref,
   InterfaceMethodref): *refInfo:                 refValue
  (NameAndType):        *nameAndTypeInfo:         nameAndType
  (MethodHandle):
                        u8:                       refKind
                        bu16:                     refIndex
  (MethodType):         bu16:                     methodType
  (Dynamic,
   InvokeDynamic):      *dynamicInfo:             dynamic
  (Unusable):           nil

struct(attributeInfo):
  bu16: nameIndex
  bu32: length
  u8:   info[length]

template accessGet(parse, parsed, output: untyped) =
  parse
  output = cast[AccessFlags](parsed.uint16)

template accessPut(encode, encoded, output) =
  output = cast[uint16](encoded)
  encode

struct(memberInfo):
  bu16 {access[AccessFlags]}: accessFlags
  bu16:                       nameIndex
  bu16:                       descriptorIndex
  bu16:                       attributesCount
  *attributeInfo:             attributes[attributesCount]

type
  ConstPool* = seq[Constant]
  CPool = ConstPool

proc cPoolGet(s: BitStream, count: uint16): ConstPool =
  let count = int(count)
  result = newSeqOfCap[Constant](count)
  var index = 0
  while index < count:
    let
      tag = s.readU8()
      disc = tag.toConstKind()
      value = constant.get(s, disc)
    result.add(value)
    if disc in {Long, Double}:
      index.inc
      result.add(Constant(disc: Unusable))
    index.inc

proc cPoolPut(s: BitStream, pool: ConstPool, _: uint16) =
  for value in pool:
    if value.disc != Unusable:
      s.writeBe(value.disc.fromConstKind())
      constant.put(s, value, value.disc)

let cPool = (get: cPoolGet, put: cPoolPut)

when defined(debug):
  template echoGet(parse, parsed, output: untyped) =
    parse
    echo parsed
    output = parsed
  template echoPut(encode, encoded, output: untyped) =
    output = encoded
    encode

struct(classFile, plugins = {converters}):
  bu32:                       _ = 0xCAFEBABE'u32
  bu16:                       minorVersion
  bu16:                       majorVersion
  bu16:                       constPoolCount
  *cPool(constPoolCount - 1): constPool
  bu16 {access[AccessFlags]}: accessFlags
  bu16:                       thisClass
  bu16:                       superClass
  bu16:                       interfacesCount
  bu16:                       interfaces[interfacesCount]
  bu16:                       fieldsCount
  *memberInfo:                fields[fieldsCount]
  bu16:                       methodsCount
  *memberInfo:                methods[methodsCount]
  bu16:                       attributesCount
  *attributeInfo:             attributes[attributesCount]

template pi(s: Stream, indent: int) =
  for i in 0..<indent:
    s.write("  ")

func byteToHex(c: uint8): (char, char) =
  const HexChars = "0123456789abcdef"
  result[1] = HexChars[c and 0xf'u8]
  result[0] = HexChars[c shr 4]

proc pprint*(refInfo: RefInfo, s: Stream, _ = 0) =
  s.write(
    "RefInfo(classIndex: ", $refInfo.classIndex,
    ", typeIndex: ", $refInfo.nameAndTypeIndex,
    ")")

proc pprint*(nameAndTypeInfo: NameAndTypeInfo, s: Stream, _ = 0) =
  s.write(
    "NameAndTypeInfo(nameIndex: ", $nameAndTypeInfo.nameIndex,
    ", descriptorIndex: ", $nameAndTypeInfo.descriptorIndex,
    ")")

proc pprint*(dynamicInfo: DynamicInfo, s: Stream, _ = 0) =
  s.write(
    "DynamicInfo(bootstrapMethodAttrIndex: ",
    $dynamicInfo.bootstrapMethodAttrIndex,
    ", nameAndTypeIndex: ", $dynamicInfo.nameAndTypeIndex,
    ")")

proc pprintBlob(blob: openArray[char], s: Stream) =
  s.write('"')
  for b in blob:
    let c = char(b)
    if c == '\t':
      s.write("\\t")
    elif c == '\n':
      s.write("\\n")
    elif c == '\r':
      s.write("\\r")
    elif c in PrintableChars - {'\x0b'..'\x0d'}:
      s.write(c)
    else:
      let (d1, d2) = byteToHex(b.uint8)
      s.write("\\x", d1, d2)
  s.write('"')

proc pprint*(`const`: Constant, s: Stream, depth = 0) =
  let depth = depth.succ
  s.write($`const`.disc, if `const`.disc != Unusable: "(" else: "")
  case `const`.disc
  of Utf8:
    s.write('\n')
    s.pi(depth)
    s.write("length: ", $`const`.utf8.len, ",\n")
    s.pi(depth)
    s.write("bytes: ")
    `const`.utf8.pprintBlob(s)
    s.write('\n')
    s.pi(depth.pred)
  of Integer:
    s.write($`const`.integer, ")")
  of Float:
    s.write($`const`.float, ")")
  of Long:
    s.write($`const`.long, ")")
  of Double:
    s.write(`const`.double.formatFloat(), ")")
  of Module, Package, Class, String:
    s.write($`const`.short)
  of Fieldref, Methodref, InterfaceMethodref:
    s.write('\n')
    s.pi(depth)
    `const`.refValue.pprint(s, depth + 1)
    s.write('\n')
    s.pi(depth.pred)
  of NameAndType:
    s.write('\n')
    s.pi(depth)
    `const`.nameAndType.pprint(s)
    s.write('\n')
    s.pi(depth.pred)
  of MethodHandle:
    s.write("refKind: ", $`const`.refKind, ", refIndex: ", $`const`.refIndex)
  of MethodType:
    s.write($`const`.methodType, ")")
  of Dynamic, InvokeDynamic:
    s.write('\n')
    `const`.dynamic.pprint(s, depth + 1)
    s.write('\n')
    s.pi(depth.pred)
  of Unusable:
    discard
  s.write(')')

proc pprint*(attribute: AttributeInfo, s: Stream, depth = 0) =
  let depth = depth.succ
  s.write("AttributeInfo(\n")
  s.pi(depth)
  s.write("attributeNameIndex: ", $attribute.nameIndex, ",\n")
  s.pi(depth)
  s.write("attributeLength: ", $attribute.length, ",\n")
  s.pi(depth)
  s.write("info: [")
  if attribute.length != 0:
    s.write('\n')
    for item in attribute.info:
      s.pi(depth.succ)
      s.write($item)
      s.write(",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth.pred)
  s.write(')')

proc pprint*(member: MemberInfo, s: Stream, depth = 0) =
  let depth = depth.succ
  s.write("MemberInfo(\n")
  s.pi(depth)
  s.write("accessFlags: ", $member.accessFlags, ",\n")
  s.pi(depth)
  s.write("nameIndex: ", $member.nameIndex, ",\n")
  s.pi(depth)
  s.write("attributesCount: ", $member.attributesCount, ",\n")
  s.pi(depth)
  s.write("attributes: [")
  if member.attributesCount != 0:
    s.write('\n')
    for attribute in member.attributes:
      s.pi(depth.succ)
      attribute.pprint(s, depth.succ)
      s.write(",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth.pred)
  s.write(')')

proc pprint*(classFile: ClassFile, s: Stream, depth = 0) =
  let depth = depth.succ
  s.write("ClassFile(\n")
  s.pi(depth)
  s.write("minorVersion: ", $classFile.minorVersion, ",\n")
  s.pi(depth)
  s.write("majorVersion: ", $classFile.majorVersion, ",\n")
  s.pi(depth)
  s.write("constPoolCount: ", $classFile.constPoolCount, ",\n")
  s.pi(depth)
  s.write("constPool: [")
  if classFile.constPool.len != 0:
    s.write("\n")
    for `const` in classFile.constPool:
      s.pi(depth.succ)
      `const`.pprint(s, depth.succ)
      s.write(",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth)
  s.write("accessFlags: ", $classFile.accessFlags, ",\n")
  s.pi(depth)
  s.write("thisClass: ", $classFile.thisClass, ",\n")
  s.pi(depth)
  s.write("superClass: ", $classFile.superClass, ",\n")
  s.pi(depth)
  s.write("interfacesCount: ", $classFile.interfacesCount, ",\n")
  s.pi(depth)
  s.write("interfaces: [")
  if classFile.interfaces.len != 0:
    s.write("\n")
    for intrfc in classFile.interfaces:
      s.pi(depth.succ)
      s.write($intrfc, ",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth)
  s.write("fieldsCount: ", $classFile.fieldsCount, ",\n")
  s.pi(depth)
  s.write("fields: [")
  if classFile.fields.len != 0:
    s.write("\n")
    for field in classFile.fields:
      s.pi(depth.succ)
      field.pprint(s, depth.succ)
      s.write(",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth)
  s.write("methodsCount: ", $classFile.methodsCount, ",\n")
  s.pi(depth)
  s.write("methods: [")
  if classFile.methods.len != 0:
    s.write("\n")
    for meth in classFile.methods:
      s.pi(depth.succ)
      meth.pprint(s, depth.succ)
      s.write(",\n")
    s.pi(depth)
  s.write("],\n")
  s.pi(depth)
  s.write("attributesCount: ", $classFile.attributesCount, ",\n")
  s.pi(depth)
  s.write("attributes: [")
  if classFile.attributes.len != 0:
    s.write("\n")
    for attribute in classFile.attributes:
      s.pi(depth.succ)
      attribute.pprint(s, depth.succ)
      s.write(",\n")
  s.pi(depth)
  s.write("],\n")
  s.pi(depth.pred)
  s.write(')')

export RefInfo,
       NameAndTypeInfo,
       DynamicInfo,
       Constant,
       AttributeInfo,
       MemberInfo,
       ClassFile

export refInfo,
       nameAndTypeInfo,
       dynamicInfo,
       constant,
       attributeInfo,
       memberInfo,
       classFile

export toClassFile, fromClassFile
