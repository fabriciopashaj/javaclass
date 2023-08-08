#########
javaclass
#########

A Java ClassFile parser and generator written in Nim using the `binarylang <https://github.com/sealmove/binarylang>`_ library.

==========
How to use
==========

.. code-block:: nim

   import javaclass
   # From string
   #  Directly
   let data = readFile("JavaClass.class")
   block:
     let
       parsedClass = data.toClassFile()
       generatedClass = parsedClass.fromClassFile()
     doAssert data == generatedClass
   #  Using a BitStream
   block:
     let
       stream = newStringBitStream(data)
       parsedClass = classFile.get(stream)
       collectorStream = newStringBitStream("")
       generatedClass = block:
         classFile.put(collectorStream, parsedClass)
         collectorStream.readStr(data.len * 8) # *8 because smth with bitstreams idk
     doAssert data == generatedClass
   # From file
   block:
     let
       stream = newFileBitStream("JavaClass.class")
       parsedClass = classFile.get(stream)
       collectorStream = newStringBitStream("")
       generatedClass = block:
         classFile.put(collectorStream, parsedClass)
         collectorStream.readStr(data.len * 8) # *8 because smth with bitstreams idk
     doAssert data == generatedClass

====
NOTE
====

This was a learning project and I don't expect anyone to need or want to use this, thus the documentation is short and dry, just some examples of how to call the parser/generator functions. If you need/want to use this library, please open an issue so that I can know and write a more complete documentation.
