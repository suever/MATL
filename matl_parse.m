function S = matl_parse(s)
%
% MATL parser.
%
% Input: string or char array containing MATL program.
%
% Output: struct array with parsed statements.
%
% Luis Mendo

if size(s,1)>1 % char array
    s = s.';
    s = s(:).'; % make a string
end

LF = char(10); % line feed in ASCII
CR = char(13); % line feed in ASCII


% Parse to separate into statements

parseControlStack = zeros(1,50); % this will hold the opening statements for 
% control statements: loops and conditional branches. Initiallized to 50,
% but will grow if needed.
parseNesting = 0;
L = numel(s);
S = struct([]); % initiallize. This will contain parsed statements.
% Three possibilites are: (1) use a struct array, (2) a cell array of scalar
% structs, or (3) a 2D cell array. I choose (1), based on the following.
%   (2) has the advantage that in each struct only the fields actually
% needed are defined (for example, a statement of type "function" doesn't
% need an "from" field), but makes it difficult to access the same field
% in different cells.
%   With (3) I need to define constants for column numbers to represent the
% "fields", and it seems to use up approximately the same amount of memory
% as (1).
%   So I use (1): struct array. Non-used fields will be empty.
%   A possible improvement would be to preallocate (with all fields) to a large number, and
% remove non-used entries at the end
pos = 1; % initial position in source string
n = 1; % statement to be parsed
while pos<=L
    if (any(s(pos)=='+-') && pos<L && any(s(pos+1)=='0123456789')) || ...
            (any(s(pos)=='+-') && pos<L-1 && s(pos+1)=='.' && any(s(pos+2)=='0123456789')) || ...
            any(s(pos)=='0123456789') || ...
            (s(pos)=='.' && pos<L && any(s(pos+1)=='0123456789'))
        % It may be a number literal such as +3.4e-5j, or a two-number colon array such as
        % -2.3:.4e2, or three-number colon array such as 10:-2.5e-1:.5e-5
        [ini, fin]   = regexp(s(pos:end), '([+-]?(\d+\.?\d*|\d*\.?\d+)(e[+-]?\d+)?[ij]?\s*:\s*){0,2}[+-]?(\d+\.?\d*|\d*\.?\d+)(e[+-]?\d+)?[ij]?', 'once');
        if ~isempty(ini) && ini==1
            if any(s(pos:pos-1+fin)==':') % It's a colon array literal
                S(n).type = 'literal.colonArray.numeric';
            else % It's a number literal
                S(n).type = 'literal.number';
            end
            S(n).source = s(pos:pos-1+fin);
            S(n).nesting = parseNesting;
            pos = pos + fin;
            n = n + 1;
        else
            error('MATL:parser:internal', 'MATL internal error while parsing number/colon array literal')
        end
    elseif any(s(pos)=='TF') % It's a row logical array
        % Consume until no longer T or F.
        [~, fin] = regexp(s(pos:end), '[TF]+', 'once');
        S(n).type = 'literal.logicalRowArray';
        S(n).source = s(pos:pos-1+fin);
        S(n).nesting = parseNesting;
        pos = pos + fin;
        n = n + 1;
    elseif s(pos)=='[' % It's an array (number, char or logical)
        % Consume until ]. There may be other [ and ] in between (although it would be a waste of characters),
        % so consume until the number of [ minus ] reaches 0
        [ini, fin] = regexp(s(pos:end), '^\[([^\[\]]*\[[^\[\]]*\])*[^\[\]]*\]', 'once');
        assert(ini==1, 'MATL:parser:internal', 'MATL internal error while parsing array literal')
        if ~validateArray(s(pos:pos-1+fin))
            error('MATL:parser:internal', 'Content not allowed in MATL array literal')
        end
        S(n).type = 'literal.array';
        S(n).source = s(pos:pos-1+fin);
        S(n).nesting = parseNesting;
        pos = pos + fin;
        n = n + 1;
    elseif s(pos)=='{' % It's a cell array. Consume until matching }. There may be other { and } in between,
        % so consume until the number of { minus } reaches 0
        fin = find(~cumsum((s(pos:end)=='{')-(s(pos:end)=='}')),1);
        assert(~isempty(fin), 'MATL:parser', 'MATL error while parsing: cell array literal not closed')
        if ~validateArray(s(pos:pos-1+fin))
            error('MATL:parser:internal', 'Content not allowed in MATL cell array literal')
        end
        S(n).type = 'literal.cellArray';
        S(n).source = s(pos:pos-1+fin);
        S(n).nesting = parseNesting;
        pos = pos + fin;
        n = n + 1;
    elseif s(pos)=='''' % It's a string. Consume until next single ' (duplicated ' symbols don't close the string).
        % Or it may be a char colon array. It has first and last operands char.
        [ini, fin] = regexp(s(pos:end), '^''([^'']|'''')*?''(?!'')((:(''([^'']|'''')*?''(?!'')|[+-]?(\d+\.?\d*|\d*\.?\d+)(e[+-]?\d+)?[ij]?))?:''([^'']|'''')*?''(?!''))?', 'once');
        % The structure of this regular expresion is: 'c((:(c|n))?:c)?', where
        % `c` (`^''([^'']|'''')*?''(?!'')`) indicates string and 
        % `n` (`[+-]?(\d+\.?\d*|\d*\.?\d+)(e[+-]?\d+)?[ij]?`) indicates number
        assert(~isempty(ini), 'MATL:parser', 'MATL error while parsing: string literal not closed')
        assert(ini==1, 'MATL:parser:internal', 'MATL internal error while parsing string/colon array literal')
        if any(s(pos:pos-1+fin)==':') % It's a (char) colon array literal
            S(n).type = 'literal.colonArray.char';
        else % It's a string
            S(n).type = 'literal.string';
        end
        S(n).source = s(pos:pos-1+fin);
        S(n).nesting = parseNesting;
        pos = pos + fin;
        n = n + 1;
    elseif any(s(pos)==['!#$&()*+-/:;<=>\^_|~' 'A':'W' 'a':'z'])
        S(n).type = 'function';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='"' % for
        % We use fields "from", "end" and "else" to keep track of the
        % structure of loops and conditional branches.
        %    parsingControlStack contains the indices of "for", "do...while" "while", "if"
        % statements found during parsing that have not been closed yet.
        %    When an "else" is found it's marked as associated with the most
        % recent statement in parsingControlStack (which should be an "if"),
        % by means of fields "else" (in the "if" statement) and "from" (in the
        % "else" statement)
        %    When and "end" is found it's marked as associated with the most
        % recent statement in parsingControlStack, by means of fields "end" (in
        % the "for", "while" or "if" statement) and "from" (in the "end"
        %    Nesting level is recorded, so that indentation can ba applied
        S(n).type = 'controlFlow.for';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        S(n).end = 0; % will be filled when a matching "end" is found
        parseNesting = parseNesting + 1; % increase nesting level
        parseControlStack(parseNesting) = n; % take note of opening statement
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='`' % doWhile
        S(n).type = 'controlFlow.doWhile';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        S(n).end = 0; % will be filled when a matching "end" is found
        parseNesting = parseNesting + 1; % increase nesting level
        parseControlStack(parseNesting) = n; % take note of opening statement
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='?' % if
        S(n).type = 'controlFlow.if';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        S(n).end = 0; % will be filled when a matching "end" is found
        parseNesting = parseNesting + 1; % increase nesting level
        parseControlStack(parseNesting) = n; % take note of opening statement
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='}' % else
        assert(parseNesting>0, 'MATL:parser', 'MATL error while parsing: ''else'' found outside any control flow structure')
        parseNesting = parseNesting - 1; % move temporarily one nesting level up
        S(n).type = 'controlFlow.else';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        parseNesting = parseNesting + 1; % restore nesting level
        m = parseControlStack(parseNesting); % innermost control structure that is open
        assert(strcmp(S(m).type,'controlFlow.if'), 'MATL:parser', 'MATL error while parsing: ''else'' not associated with ''if''')
        S(m).else = n; % associate opening statement with this
        S(n).from = m; % associate this with opening statement
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='@' % index of for/do...while/while iteration
        assert(parseNesting>0, 'MATL:parser', 'MATL error while parsing: ''@'' found outside any control flow structure')
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        success = false;
        for m = parseControlStack(parseNesting:-1:1); % from innermost to outermost control structure
            if strcmp(S(m).type,'controlFlow.for')
                S(n).type = 'controlFlow.forValue';
                success = true;
            elseif strcmp(S(m).type,'controlFlow.doWhile')
                S(n).type = 'controlFlow.doWhileIndex';
                success = true;
            elseif strcmp(S(m).type,'controlFlow.while')
                S(n).type = 'controlFlow.whileIndex';
                success = true;
            end
            if success
                S(n).from = m;
                break
            end
        end
        if ~success
            error('MATL:parser', 'MATL error while parsing: ''@'' is not within any ''for'' or ''while'' loop')
        end
        pos = pos + 1;
        n = n + 1;
    elseif s(pos) =='.' % conditional break
        assert(parseNesting>0, 'MATL:parser', 'MATL error while parsing: ''conditional break'' found outside any control flow structure')
        S(n).type = 'controlFlow.conditionalBreak';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        success = false;
        for m = parseControlStack(parseNesting:-1:1); % from innermost to outermost control structure
            if any(strcmp(S(m).type,{'controlFlow.for' 'controlFlow.doWhile' 'controlFlow.while'}))
                S(n).from = m; % associate this with opening statement
                success = true;
                break % no need to look for any longer in the control stack
            end
        end
        if ~success
            error('MATL:parser', 'MATL error while parsing: ''conditional break'' is not within any ''for'', ''do...while'' or ''while'' loop')
        end
        pos = pos + 1;
        n = n + 1;  
    elseif s(pos)==']' % end (of for, do...while, while, if)
        assert(parseNesting>0, 'MATL:parser', 'MATL error while parsing: ''end'' found outside any control flow structure')
        m = parseControlStack(parseNesting); % innermost control structure that is open
        S(m).end = n; % associate opening with this
        S(n).from = m; % associate this with opening statement
        parseControlStack(parseNesting) = 0; % this loop/conditional branch is closed
        parseNesting = parseNesting - 1; % decrease nesting level
        S(n).type = 'controlFlow.end';
        S(n).source = s(pos);
        S(n).nesting = parseNesting;
        pos = pos + 1;
        n = n + 1;
    elseif s(pos)=='%' % consume until LF or CR. Don't store in S
        [ini, fin] = regexp(s(pos:end),'^%[^\r\n]*[\r\n]?');
        assert(ini==1, 'MATL:parser:internal', 'MATL internal error while parsing comment literal')
        pos = pos + fin;
        % There's no statement. Just move `pos` forward. Statement count n is not incremented
    elseif any(s(pos)==[', ' LF CR]) % do nothing, just consume (but that
        % doesn't mean these characters are useless. They are sometimes needed
        % as separators)
        pos = pos + 1;
        % There's no statement. Just move `pos` forward. Statement count n is not incremented
    elseif s(pos)=='X' && pos<L
        if s(pos+1)=='`' % while
            S(n).type = 'controlFlow.while';
            S(n).source = s([pos pos+1]);
            S(n).nesting = parseNesting;
            S(n).end = 0; % will be filled when a matching "end" is found
            parseNesting = parseNesting + 1; % increase nesting level
            parseControlStack(parseNesting) = n; % take note of opening statement
        elseif s(pos+1)=='.' % conditional continue
            assert(parseNesting>0, 'MATL:parser', 'MATL error while parsing: ''conditional continue'' found outside any control flow structure')
            S(n).type = 'controlFlow.conditionalContinue';
            S(n).source = s([pos pos+1]);
            S(n).nesting = parseNesting;
            success = false;
            for m = parseControlStack(parseNesting:-1:1); % from innermost to outermost control structure
                if any(strcmp(S(m).type,{'controlFlow.for' 'controlFlow.doWhile' 'controlFlow.while'}))
                    S(n).from = m; % associate this with opening statement
                    success = true;
                    break % no need to look for in the control stack any longer
                end
            end
            if ~success
                error('MATL:parser', 'MATL error while parsing: ''conditional continue'' is not within any ''for'' loop')
            end
        elseif any(s(pos+1)==' ') % Not currently used after X. We can filter here or leave it to the compiler
            error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> not recognized at position %d', s([pos pos+1]), pos)
        else
            S(n).type = 'function';
            S(n).source = s([pos pos+1]);
            S(n).nesting = parseNesting;
        end
        pos = pos + 2;
        n = n + 1;
    elseif s(pos)=='Y' && pos<L
        if any(s(pos+1)==' ') % Not used after Y
            error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> not recognized at position %d', s([pos pos+1]), pos)
        else
            S(n).type = 'function';
            S(n).source = s([pos pos+1]);
            S(n).nesting = parseNesting;
        end
        pos = pos + 2;
        n = n + 1;
    elseif s(pos)=='Z' && pos<L
        if any(s(pos+1)==' ') % Not used after Z.
            error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> not recognized at position %d', s([pos pos+1]), pos)
        else
            S(n).type = 'function';
            S(n).source = s([pos pos+1]);
            S(n).nesting = parseNesting;
        end
        pos = pos + 2;
        n = n + 1;
    elseif any(s(pos)=='''') % Not allowed.
        error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> not recognized at position %d', s(pos), pos)
    elseif any(s(pos)=='XYZ') && pos==L
        error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> not recognized at position %d', s(pos), pos)
    else
        error('MATL:parser:internal', 'MATL internal error while parsing')
    end
end

if isfield(S,'end') && any(cellfun(@(x) isequal(x,0), {S.end}))
    unclosed = find(cellfun(@(x) isequal(x,0), {S.end}), 1);
    error('MATL:parser', 'MATL error while parsing: <strong>%s</strong> statement has no matching <strong>]</strong>', S(unclosed).source)
end

end

function valid = validateArray(str)
% valid = isempty(regexp(str, '^[^'']*(''[^'']*''[^'']*)*[a-zA-Z]{2}', ...
% 'once')); % Make sure it doesn't contain two letters in a row outside of a string
valid = isempty(regexp(str, '^[^'']*(''[^'']*''[^'']*)*[a-df-ik-zA-EH-LOQ-SU-XZ]', 'once')) & ...
    isempty(regexp(str, '^[^'']*(''[^'']*''[^'']*)*[a-zA-Z]{2}', 'once'));
% First line: make sure it doesn't contain letters other than e, j, F, M, N, P, Q, T, Y outside strings 
% Second line: make sure it doesn't contain two letters in a row outside strings
end
