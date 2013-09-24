vars = require './vars.js'

module.exports = class NoTabs

    rule:
        name: 'undefined_variables'

        # This isn't REALLY configurable, I just want to be clear that hoisted
        # variables are considered an error.
        allowHoisting: false
        level : 'error'
        message : 'Undefinded variable'
        description : 'Detect undefined variables'

    lintAST : (node, @astApi) ->
        @depth = 0
        @scopes = []
        @newScope()

        defineAll = (list) =>
            for v in list
                @currentScope[v] = { defined: -1, used: true }

        # `this` is really a keyword, but it shows up as a variable.
        # Simulating a global `this` is good enough for undefined/unused
        # variable detection.
        vars.reservedVars.push 'this'
        defineAll vars.reservedVars
        defineAll vars.ecmaIdentifiers
        defineAll vars.browser
        defineAll vars.devel
        defineAll vars.node

        @lintNode node

        @popScope()

        # If this ever happens it indicates something is wrong in the code.
        # Probably not something a user could ever trigger.
        if @scopes.length isnt 0
            throw new Error "Error walking AST for undefined_variables"
        undefined

    newScope: ->
        parentScope = @currentScope

        Scope = ->
        if parentScope?
            Scope.prototype = parentScope

        cs = new Scope
        @scopes.push cs
        @currentScope = cs
        console.assert @currentScope in @scopes, 'foo'
        undefined

    newVariable: (variable, options = {}) ->
        return unless variable?
        base = variable.base
        name = base.value


        # Assigning a property to an object. This needs to verify that
        # the object exists.
        if variable.properties?.length > 0
            # Catch assigning a property to an undefined variable
            @checkExists variable.base

            # Make sure array style access is using defined variables
            for index, p of variable.properties
                if p.index?
                    @checkExists p.index.base
            return

        if name?
            unless @currentScope[name]?
                options.defined = base.locationData.first_line+1
                options.used = false
                @currentScope[name] = options

    popScope: ->
        exitingScope = @scopes.pop()
        @currentScope = @scopes[@scopes.length - 1]
        for own name, data of exitingScope
            unless data.used

                # When iterating over an object you must define a variable for
                # the index even if you only need the values. Similarly you
                # might define multiple parameters in a function when only
                # needing the last one.
                #
                # dependsOn allows an exception in these cases where if you
                # defined an index for the loop then using the value is
                # sufficient to avoid an unused variable error.
                current = data
                while current? and current.used is false
                    current = exitingScope[current.dependsOn]

                unless current?.used
                    @errors.push @astApi.createError {
                        context: name
                        message : 'Unused variable'
                        lineNumber: data.defined
                    }

        undefined

    checkExists: (base) ->
        value = base?.value

        # Literal values like strings and integers aren't assignable but get
        # passed through here when used as arguments for a function.  A falsy
        # check won't work with ?(), it needs to be false.
        if not base? or base?.isAssignable?() is false
            return true

        if value? and @currentScope[value]?
            @currentScope[value].used = true
        else if value?
            @errors.push @astApi.createError {
                context: value
                message : 'Undefined variable'
                lineNumber: base.locationData.first_line+1
            }
            return false
        true

    lintNode: (node) ->

        # Get the complexity of the current node.
        name = node.constructor.name
        # @indent @level, name + " scope? #{@currentScope in @scopes}"

        if name is 'Code'
            @newScope()
            lastParam = undefined
            for param in node.params by -1
                # Everything seems to have a variable with a `.base` and
                # potentially a `.properties`. Since params seem to lack a base
                # this will create that fake level to make them match
                # @newVariable calls everywhere else

                param.base = param.name
                @newVariable param,
                    dependsOn: lastParam

                lastParam = param.name.value

        # Processing variables declared in a block seem
        else if name is 'Block-disabled'
            # IDK if I like this, it modifies the AST.
            # node.makeReturn()

            for exp in node.expressions
                # Assignment somewhere?

                if exp.variable? and exp.value?
                    # @newVariable exp.variable
                    undefined
                # Splats have a source attribute instead of a variable.
                else if exp.source?
                    @newVariable exp.source


        else if name is 'Comment'

            # http://stackoverflow.com/a/3537914/35247
            # JS Regex doesn't support capturing all of a repeating group.
            commentRegex = ///

                global
                (?:      # non capturing
                    \s
                    [\w\d]+
                )*
            ///g

            line = node.location.first_line+1
            tmp = commentRegex.exec(node.comment)
            for variable in tmp[0].split(' ')[1..]
                @currentScope[variable] = { defined: line, used: false }

        else if name is 'Class'
            @newVariable node.variable
        else if name is 'Assign'

            @checkExists node.value
            if node.context isnt 'object'
                # Once it's in the destructuring process this needs to dig
                # through the values to find newly defined variables.
                recurseValues = (n) =>
                    if n.value?
                        recurseValues n.value
                    else
                        if n.base.objects?
                            for o in n.base.objects
                                recurseValues o
                        else
                            @newVariable n
                    undefined

                # This is a destructuring assignment
                if node.variable.base.objects?
                    for o in node.variable.base.objects
                        if o.value?
                            recurseValues o.value
                        else
                            recurseValues o
                else
                    @newVariable node.variable

        else if name is 'Splat'
            @checkExists node.name.base
        else if name is 'Op'
            @checkExists node.first.base
            if node.second?
                @checkExists node.second.base
        else if name is 'If'
            if node.condition.expression?
                @checkExists node.condition.expression.base

            if node.condition.constructor.name is 'Value'
                @checkExists node.condition.base

        else if name is 'In'
            @checkExists node.object.base
            @checkExists node.array.base
        else if name is 'For'

            if node.name?
                @newVariable { base: node.name }

            if node.index?
                @newVariable { base: node.index },
                    dependsOn: node.name?.value

            @checkExists node.source.base
        else if name is 'Call'

            if node.variable?
                @checkExists node.variable.base
            for arg in node.args
                @checkExists arg.base

        else
            undefined

        @lintChildren(node)

        # Return needs to go depth first.
        if name is 'Return'
            # TODO: Figure out the right patterns, right now this is all just
            # guessing
            if node.expression?
                @checkExists node.expression.variable?.base
                @checkExists node.expression
                @checkExists node.expressionbase

        else if name is 'Code'
            @popScope()

        undefined

    indent: (num, suffix) ->
        if num <= 10
            console.log (new Array(parseInt(num)+1)).join(' ')+num+suffix

    level: 0
    lintChildren: (node) ->

        @level++
        node.eachChild (childNode) =>
            @lintNode(childNode) if childNode
            true
        @level--

