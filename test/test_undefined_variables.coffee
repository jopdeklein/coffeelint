path = require 'path'
vows = require 'vows'
assert = require 'assert'
coffeelint = require path.join('..', 'src', 'coffeelint')

isUnused = (err, name) ->
    assert err?, "Expected error for #{name}"
    assert.isTrue err.message is 'Unused variable',
        "Expected: Unused variable " +
        "Actual: #{err.message}"

    # Why does VowsJS require me to reinvent an assertion just to be able to
    # read the result?
    assert.isTrue err.context is name,
        "Expected: #{name} " +
        "Actual: #{err.context}"

isUndefined = (err, name) ->
    assert err?, "Expected error for #{name}"
    assert.isTrue err.message is 'Undefined variable',
        "Expected: Undefined variable " +
        "Actual: #{err.message}"

    assert.isTrue err.context is name,
        "Expected: #{name} " +
        "Actual: #{err.context}"

# When multiple errors occur on the same line they come back in a
# non-deterministic order. This doesn't generally matter except the code is
# easier to read here if the order is known. This will re-sort so that errors
# on the same line are in alphabetical order.
errorSorter = (a, b) ->
    if a.lineNumber < b.lineNumber
        -1
    else if a.lineNumber > b.lineNumber
        1
    else
        if a.context < b.context
            -1
        else if a.context > b.context
            1
        else
            0

vows.describe('undefined_variables').addBatch({

    'Undefined Variables':
        topic:
            """
            obj.foo = 'foo'
            obj2[missingIndex] = 'foo'

            fn(param)
            instance.bar(barParam)

            class Namespace.MyClass

              test: -> undefined

            new MissingClass(missingParameter)

            window.alert param[badIndex]

            """

        'undefined variables': (source) ->
            errors = coffeelint.lint source,
                {undefined_variables: {'level':'error'}}
            errors.sort errorSorter

            isUndefined errors.shift(), 'obj'

            isUndefined errors.shift(), 'missingIndex'
            isUndefined errors.shift(), 'obj2'

            isUndefined errors.shift(), 'fn'
            isUndefined errors.shift(), 'param'

            isUndefined errors.shift(), 'barParam'
            isUndefined errors.shift(), 'instance'

            isUndefined errors.shift(), 'Namespace'

            isUndefined errors.shift(), 'MissingClass'
            isUndefined errors.shift(), 'missingParameter'

            # isUndefined errors.shift(), 'badIndex'
            isUndefined errors.shift(), 'param'

            assert.isEmpty(errors)

    'Unused Variables' :

        topic :
            """
            noop = -> undefined

            ###
            # global someGlobal
            ###

            unusedFunction = -> undefined

            class ParentClass

            class UnusedClass extends ParentClass

              foo: (a, b, extraParam) ->
                noop b

              bar: (x, y, z) ->
                undefined

            { foo: destructuredObject } = noop

            { outer : { inner: deepDestructuredObject  } } = noop

            [ destructuredArray ] = noop
            [ [ deepDestructuredArray ] ] = noop

            for objIndex, objValue of {}
              undefined

            # Similar to parameters using objValue2 prevents an unused variable
            # error on objIndex2.
            for objIndex2, objValue2 of {}
              noop objValue2

            for arrValue, arrIndex of []
              undefined

            for arrValue2, arrIndex2 of []
              noop arrIndex2

            splatFn = (splat...) -> undefined

            destructuringFn = ([destructuredParameter]) -> undefined

            # lastParam is NOT unused, but it was being wrongly counted as
            # unused.
            lastParam = undefined
            noop { lp: lastParam }
            window.foo = { lp: lastParam }

            cache = undefined
            window.getCache = ->
              cache ?= Math.random()

            """

        'unused variables' : (source) ->

            errors = coffeelint.lint source,
                {undefined_variables: {'level':'error'}}

            errors.sort errorSorter

            isUnused errors.shift(), 'unusedFunction'
            isUnused errors.shift(), 'UnusedClass'

            # Because variable b is used in the function a is considered to
            # have been used since it's no longer optional.
            isUnused errors.shift(), 'extraParam'

            isUnused errors.shift(), 'x'
            isUnused errors.shift(), 'y'
            isUnused errors.shift(), 'z'

            isUnused errors.shift(), 'destructuredObject'
            isUnused errors.shift(), 'deepDestructuredObject'
            isUnused errors.shift(), 'destructuredArray'
            isUnused errors.shift(), 'deepDestructuredArray'

            isUnused errors.shift(), 'objIndex'
            isUnused errors.shift(), 'objValue'

            isUnused errors.shift(), 'arrIndex'
            isUnused errors.shift(), 'arrValue'

            isUnused errors.shift(), 'splat'
            isUnused errors.shift(), 'splatFn'

            # isUnused errors.shift(), 'destructuredParameter'
            isUnused errors.shift(), 'destructuringFn'

            assert.isEmpty(errors)

}).export(module)
