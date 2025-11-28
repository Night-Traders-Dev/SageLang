#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "lexer.h"
#include "ast.h"
#include "token.h"

static Token current_token;
static Token previous_token;

static void advance_parser() {
    previous_token = current_token;
    current_token = scan_token();
}

void parser_init() {
    advance_parser();
}

static int check(TokenType type) {
    return current_token.type == type;
}

static int match(TokenType type) {
    if (current_token.type == type) {
        advance_parser();
        return 1;
    }
    return 0;
}

static void consume(TokenType type, const char* message) {
    if (current_token.type == type) {
        advance_parser();
        return;
    }
    fprintf(stderr, "[Line %d] Error: %s (Got type %d)\n", current_token.line, message, current_token.type);
    exit(1);
}

// Forward declarations
static Expr* expression();
static Expr* postfix();
static Stmt* declaration();
static Stmt* statement();
static Stmt* block();

static Stmt* for_statement() {
    if (!check(TOKEN_IDENTIFIER)) {
        fprintf(stderr, "[Line %d] Error: Expect loop variable after 'for'.\n", current_token.line);
        exit(1);
    }
    
    Token var = current_token;
    advance_parser();

    consume(TOKEN_IN, "Expect 'in' after loop variable.");

    Expr* iterable = expression();
    consume(TOKEN_COLON, "Expect ':' after for clause.");
    consume(TOKEN_NEWLINE, "Expect newline after for clause.");

    Stmt* body = block();

    return new_for_stmt(var, iterable, body);
}

// primary -> NUMBER | STRING | BOOLEAN | NIL | SELF | ( expr/tuple ) | [ array ] | { dict } | IDENTIFIER | CALL
static Expr* primary() {
    // Literals
    if (match(TOKEN_FALSE)) return new_bool_expr(0);
    if (match(TOKEN_TRUE))  return new_bool_expr(1);
    if (match(TOKEN_NIL))   return new_nil_expr();
    
    // Self keyword (treated as variable)
    if (match(TOKEN_SELF)) {
        Token self_token = previous_token;
        return new_variable_expr(self_token);
    }

    // Parentheses: ( expr ) or tuple (a, b, c)
    if (match(TOKEN_LPAREN)) {
        if (match(TOKEN_RPAREN)) {
            return new_tuple_expr(NULL, 0);
        }

        Expr* first = expression();
        
        if (match(TOKEN_COMMA)) {
            Expr** elements = NULL;
            int count = 0;
            int capacity = 4;
            elements = malloc(sizeof(Expr*) * capacity);
            elements[count++] = first;
            
            if (!check(TOKEN_RPAREN)) {
                do {
                    if (count >= capacity) {
                        capacity *= 2;
                        elements = realloc(elements, sizeof(Expr*) * capacity);
                    }
                    elements[count++] = expression();
                } while (match(TOKEN_COMMA) && !check(TOKEN_RPAREN));
            }
            
            consume(TOKEN_RPAREN, "Expect ')' after tuple elements.");
            return new_tuple_expr(elements, count);
        }
        
        consume(TOKEN_RPAREN, "Expect ')' after expression.");
        return first;
    }

    // Dictionary Literals
    if (match(TOKEN_LBRACE)) {
        char** keys = NULL;
        Expr** values = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACE)) {
            do {
                consume(TOKEN_STRING, "Expect string key in dictionary.");
                Token key_token = previous_token;
                
                int len = key_token.length - 2;
                char* key = malloc(len + 1);
                memcpy(key, key_token.start + 1, len);
                key[len] = '\0';
                
                consume(TOKEN_COLON, "Expect ':' after dictionary key.");
                Expr* value = expression();
                
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    keys = realloc(keys, sizeof(char*) * capacity);
                    values = realloc(values, sizeof(Expr*) * capacity);
                }
                keys[count] = key;
                values[count] = value;
                count++;
            } while (match(TOKEN_COMMA) && !check(TOKEN_RBRACE));
        }
        
        consume(TOKEN_RBRACE, "Expect '}' after dictionary elements.");
        return new_dict_expr(keys, values, count);
    }

    // Array Literals
    if (match(TOKEN_LBRACKET)) {
        Expr** elements = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACKET)) {
            do {
                Expr* elem = expression();
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    elements = realloc(elements, sizeof(Expr*) * capacity);
                }
                elements[count++] = elem;
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RBRACKET, "Expect ']' after array elements.");
        return new_array_expr(elements, count);
    }

    // Numbers
    if (match(TOKEN_NUMBER)) {
        double val = strtod(previous_token.start, NULL);
        return new_number_expr(val);
    }

    // Strings
    if (match(TOKEN_STRING)) {
        Token t = previous_token;
        int len = t.length - 2;
        char* str = malloc(len + 1);
        memcpy(str, t.start + 1, len);
        str[len] = '\0';
        return new_string_expr(str);
    }

    // Identifiers & Function/Constructor Calls
    if (match(TOKEN_IDENTIFIER)) {
        Token name = previous_token;

        if (match(TOKEN_LPAREN)) {
            Expr** args = NULL;
            int count = 0;
            int capacity = 0;

            if (!check(TOKEN_RPAREN)) {
                do {
                    Expr* arg = expression();
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        args = realloc(args, sizeof(Expr*) * capacity);
                    }
                    args[count++] = arg;
                } while (match(TOKEN_COMMA));
            }
            consume(TOKEN_RPAREN, "Expect ')' after arguments.");
            return new_call_expr(name, args, count);
        }

        return new_variable_expr(name);
    }

    fprintf(stderr, "[Line %d] Expect expression.\n", current_token.line);
    exit(1);
}

static Expr* postfix() {
    Expr* expr = primary();

    while (1) {
        if (match(TOKEN_LBRACKET)) {
            Expr* start_or_index = NULL;
            Expr* end = NULL;
            
            if (!check(TOKEN_COLON)) {
                start_or_index = expression();
            }
            
            if (match(TOKEN_COLON)) {
                Expr* start = start_or_index;
                
                if (!check(TOKEN_RBRACKET)) {
                    end = expression();
                }
                
                consume(TOKEN_RBRACKET, "Expect ']' after slice.");
                expr = new_slice_expr(expr, start, end);
            } else {
                consume(TOKEN_RBRACKET, "Expect ']' after index.");
                expr = new_index_expr(expr, start_or_index);
            }
        } else if (match(TOKEN_DOT)) {
            // Property access: obj.property or method call obj.method()
            consume(TOKEN_IDENTIFIER, "Expect property name after '.'.");
            Token property = previous_token;
            
            // Check for method call: obj.method(args)
            if (match(TOKEN_LPAREN)) {
                // Parse arguments
                Expr** args = NULL;
                int count = 0;
                int capacity = 0;

                if (!check(TOKEN_RPAREN)) {
                    do {
                        Expr* arg = expression();
                        if (count >= capacity) {
                            capacity = capacity == 0 ? 4 : capacity * 2;
                            args = realloc(args, sizeof(Expr*) * capacity);
                        }
                        args[count++] = arg;
                    } while (match(TOKEN_COMMA));
                }
                consume(TOKEN_RPAREN, "Expect ')' after arguments.");
                
                // Create a special call expression that includes the object
                // We'll store the object in expr and create a call with the method name
                // For now, we create a GET expr and the interpreter will handle it
                // Actually, we need a different approach - let's use a special marker
                
                // Store the GET expression with method name, then wrap in a CALL
                // The interpreter will detect CALL of a GET and treat it as a method call
                Expr* get_expr = new_get_expr(expr, property);
                expr = new_call_expr(property, args, count);
                // Store the object in the first "arg" position secretly
                // Actually, let's modify call to store object separately
                // For now: reuse CALL but interpreter detects pattern
                
                // Better approach: modify CallExpr to optionally store object
                // For now, let's make the interpreter smarter
                expr->as.call.args = realloc(expr->as.call.args, sizeof(Expr*) * (count + 1));
                // Shift args right
                for (int i = count; i > 0; i--) {
                    expr->as.call.args[i] = expr->as.call.args[i-1];
                }
                // Store GET expression as first arg (special marker)
                expr->as.call.args[0] = get_expr;
                expr->as.call.arg_count = count + 1; // Include hidden arg
            } else {
                // Just property access
                expr = new_get_expr(expr, property);
            }
        } else {
            break;
        }
    }

    return expr;
}

static Expr* term() {
    Expr* expr = postfix();
    while (match(TOKEN_STAR) || match(TOKEN_SLASH)) {
        Token op = previous_token;
        Expr* right = postfix();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* addition() {
    Expr* expr = term();
    while (match(TOKEN_PLUS) || match(TOKEN_MINUS)) {
        Token op = previous_token;
        Expr* right = term();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* comparison() {
    Expr* expr = addition();
    while (match(TOKEN_GT) || match(TOKEN_LT) || match(TOKEN_GTE) || match(TOKEN_LTE)) {
        Token op = previous_token;
        Expr* right = addition();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* equality() {
    Expr* expr = comparison();
    while (match(TOKEN_EQ) || match(TOKEN_NEQ)) {
        Token op = previous_token;
        Expr* right = comparison();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* logical_and() {
    Expr* expr = equality();
    while (match(TOKEN_AND)) {
        Token op = previous_token;
        Expr* right = equality();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* logical_or() {
    Expr* expr = logical_and();
    while (match(TOKEN_OR)) {
        Token op = previous_token;
        Expr* right = logical_and();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* assignment() {
    Expr* expr = logical_or();
    
    // Check for property assignment: obj.prop = value
    if (expr->type == EXPR_GET && match(TOKEN_ASSIGN)) {
        Expr* value = assignment();
        return new_set_expr(expr->as.get.object, expr->as.get.property, value);
    }
    
    return expr;
}

static Expr* expression() {
    return assignment();
}

static Stmt* print_statement() {
    Expr* value = expression();
    return new_print_stmt(value);
}

static Stmt* block() {
    consume(TOKEN_INDENT, "Expect indentation after block start.");
    
    Stmt* head = NULL;
    Stmt* current = NULL;

    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        if (match(TOKEN_NEWLINE)) {
            continue;
        }

        Stmt* stmt = declaration();
        
        if (head == NULL) {
            head = stmt;
            current = head;
        } else {
            current->next = stmt;
            current = stmt;
        }
    }

    consume(TOKEN_DEDENT, "Expect dedent at end of block.");
    return new_block_stmt(head);
}

static Stmt* if_statement() {
    Expr* condition = expression();
    consume(TOKEN_COLON, "Expect ':' after if condition.");
    consume(TOKEN_NEWLINE, "Expect newline after if condition.");
    Stmt* then_branch = block();

    Stmt* else_branch = NULL;
    if (match(TOKEN_ELSE)) {
        consume(TOKEN_COLON, "Expect ':' after else.");
        consume(TOKEN_NEWLINE, "Expect newline after else.");
        else_branch = block();
    }
    
    return new_if_stmt(condition, then_branch, else_branch);
}

static Stmt* while_statement() {
    Expr* condition = expression();
    consume(TOKEN_COLON, "Expect ':' after while condition.");
    consume(TOKEN_NEWLINE, "Expect newline after while condition.");
    Stmt* body = block();
    return new_while_stmt(condition, body);
}

// PHASE 7: Match statement parser
static Stmt* match_statement() {
    // match value:
    Expr* value = expression();
    consume(TOKEN_COLON, "Expect ':' after match value.");
    consume(TOKEN_NEWLINE, "Expect newline after match statement.");
    consume(TOKEN_INDENT, "Expect indentation in match body.");
    
    // Parse case clauses
    CaseClause** cases = NULL;
    int case_count = 0;
    int case_capacity = 0;
    Stmt* default_case = NULL;
    
    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        // Skip blank lines
        if (match(TOKEN_NEWLINE)) {
            continue;
        }
        
        if (match(TOKEN_CASE)) {
            // case pattern:
            Expr* pattern = expression();
            consume(TOKEN_COLON, "Expect ':' after case pattern.");
            consume(TOKEN_NEWLINE, "Expect newline after case clause.");
            
            // Parse case body (single statement or block)
            Stmt* case_body;
            if (check(TOKEN_INDENT)) {
                case_body = block();
            } else {
                // Single statement on same line (after indent)
                case_body = statement();
                match(TOKEN_NEWLINE);
            }
            
            // Create case clause
            CaseClause* clause = new_case_clause(pattern, case_body);
            
            // Add to cases array
            if (case_count >= case_capacity) {
                case_capacity = case_capacity == 0 ? 4 : case_capacity * 2;
                cases = realloc(cases, sizeof(CaseClause*) * case_capacity);
            }
            cases[case_count++] = clause;
            
        } else if (match(TOKEN_DEFAULT)) {
            // default:
            consume(TOKEN_COLON, "Expect ':' after default.");
            consume(TOKEN_NEWLINE, "Expect newline after default clause.");
            
            // Parse default body
            if (check(TOKEN_INDENT)) {
                default_case = block();
            } else {
                default_case = statement();
                match(TOKEN_NEWLINE);
            }
            
            // Default should be last, break out
            break;
        } else {
            fprintf(stderr, "[Line %d] Error: Expect 'case' or 'default' in match body.\n", current_token.line);
            exit(1);
        }
    }
    
    consume(TOKEN_DEDENT, "Expect dedent at end of match statement.");
    
    return new_match_stmt(value, cases, case_count, default_case);
}

static Stmt* proc_declaration() {
    // Accept TOKEN_IDENTIFIER or TOKEN_INIT (for init method)
    if (current_token.type == TOKEN_IDENTIFIER || current_token.type == TOKEN_INIT) {
        Token name = current_token;
        advance_parser();
        
        consume(TOKEN_LPAREN, "Expect '(' after procedure name.");

        Token* params = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RPAREN)) {
            do {
                // Accept SELF or IDENTIFIER for parameters
                if (current_token.type == TOKEN_SELF || current_token.type == TOKEN_IDENTIFIER) {
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        params = realloc(params, sizeof(Token) * capacity);
                    }
                    params[count++] = current_token;
                    advance_parser();
                } else {
                    fprintf(stderr, "[Line %d] Error: Expect parameter name.\n", current_token.line);
                    exit(1);
                }
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RPAREN, "Expect ')' after parameters.");
        consume(TOKEN_COLON, "Expect ':' after procedure signature.");
        consume(TOKEN_NEWLINE, "Expect newline before procedure body.");
        Stmt* body = block();

        return new_proc_stmt(name, params, count, body);
    }
    
    fprintf(stderr, "[Line %d] Error: Expect procedure name.\n", current_token.line);
    exit(1);
}

static Stmt* class_declaration() {
    consume(TOKEN_IDENTIFIER, "Expect class name.");
    Token name = previous_token;
    
    // Check for inheritance: class Child(Parent):
    Token parent;
    int has_parent = 0;
    if (match(TOKEN_LPAREN)) {
        consume(TOKEN_IDENTIFIER, "Expect parent class name.");
        parent = previous_token;
        consume(TOKEN_RPAREN, "Expect ')' after parent class.");
        has_parent = 1;
    }
    
    consume(TOKEN_COLON, "Expect ':' after class header.");
    consume(TOKEN_NEWLINE, "Expect newline after class header.");
    consume(TOKEN_INDENT, "Expect indentation in class body.");
    
    // Parse methods (all methods are proc declarations)
    Stmt* method_head = NULL;
    Stmt* method_current = NULL;
    
    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        if (match(TOKEN_NEWLINE)) {
            continue;
        }
        
        if (match(TOKEN_PROC)) {
            Stmt* method = proc_declaration();
            
            if (method_head == NULL) {
                method_head = method;
                method_current = method;
            } else {
                method_current->next = method;
                method_current = method;
            }
        } else {
            fprintf(stderr, "[Line %d] Only methods allowed in class body.\n", current_token.line);
            exit(1);
        }
    }
    
    consume(TOKEN_DEDENT, "Expect dedent after class body.");
    
    return new_class_stmt(name, parent, has_parent, method_head);
}

static Stmt* statement() {
    if (match(TOKEN_PRINT)) return print_statement();
    if (match(TOKEN_IF)) return if_statement();
    if (match(TOKEN_WHILE)) return while_statement();
    if (match(TOKEN_FOR)) return for_statement();
    if (match(TOKEN_MATCH)) return match_statement();  // PHASE 7: Match statement
    if (match(TOKEN_BREAK)) return new_break_stmt();
    if (match(TOKEN_CONTINUE)) return new_continue_stmt();

    Expr* expr = expression();
    return new_expr_stmt(expr);
}

static Stmt* declaration() {
    while (match(TOKEN_NEWLINE));

    if (check(TOKEN_DEDENT) || check(TOKEN_EOF)) {
        return NULL;
    }

    if (match(TOKEN_CLASS)) return class_declaration();
    if (match(TOKEN_PROC)) return proc_declaration();

    if (match(TOKEN_RETURN)) {
        Expr* value = NULL;
        if (!check(TOKEN_NEWLINE)) {
            value = expression();
        }
        match(TOKEN_NEWLINE);
        return new_return_stmt(value);
    }

    if (match(TOKEN_LET)) {
        consume(TOKEN_IDENTIFIER, "Expect variable name.");
        Token name = previous_token;

        Expr* initializer = NULL;
        if (match(TOKEN_ASSIGN)) {
            initializer = expression();
        }

        Stmt* stmt = new_let_stmt(name, initializer);
        match(TOKEN_NEWLINE);
        return stmt;
    }

    Stmt* stmt = statement();
    match(TOKEN_NEWLINE);
    return stmt;
}

Stmt* parse() {
    while (current_token.type == TOKEN_NEWLINE) {
        advance_parser();
    }

    if (current_token.type == TOKEN_EOF) return NULL;
    return declaration();
}