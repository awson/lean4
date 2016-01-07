/*
Copyright (c) 2015 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Author: Leonardo de Moura
*/
#pragma once
#include "library/expr_lt.h"
#include "library/type_context.h"

namespace lean {
/** \brief Function parameter information. It is used by \c fun_info_manager. */
class param_info {
    /* m_specialized is true if the result of fun_info has been specifialized
       using this argument.
       For example, consider the function

             f : Pi (A : Type), A -> A

       Now, suppse we request get_specialize fun_info for the application

             f unit a

       fun_info_manager returns two param_info objects:
       1) m_specialized = true, m_is_dep = true
       2) m_subsingleton = true, m_deps = {0}

       Note that, in general, the second argument of f is not a subsingleton,
       but it is in this particular case/specialization.

       \remark This bit is only set if it is a dependent parameter (i.e., m_is_dep is true).

       Moreover, we only set m_specialized IF another parameter
       becomes a subsingleton or proposition. */
    unsigned       m_specialized:1;
    unsigned       m_implicit:1;
    unsigned       m_inst_implicit:1;
    unsigned       m_prop:1;
    unsigned       m_subsingleton:1;
    unsigned       m_is_dep:1; // true if rest depends on this parameter
    list<unsigned> m_deps; // previous arguments it depends on
public:
    param_info(bool spec, bool imp, bool inst_imp, bool prop, bool sub, bool is_dep, list<unsigned> const & deps):
        m_specialized(spec), m_implicit(imp), m_inst_implicit(inst_imp), m_prop(prop), m_subsingleton(sub),
        m_is_dep(is_dep), m_deps(deps) {}
    list<unsigned> const & get_dependencies() const { return m_deps; }
    bool specialized() const { return m_specialized; }
    bool is_implicit() const { return m_implicit; }
    bool is_inst_implicit() const { return m_inst_implicit; }
    bool is_prop() const { return m_prop; }
    bool is_subsingleton() const { return m_subsingleton; }
    bool is_dep() const { return m_is_dep; }
};

/** \brief Function information produced by \c fun_info_manager */
class fun_info {
    unsigned         m_arity;
    list<param_info> m_params_info;
    list<unsigned>   m_deps; // resulting type dependencies
public:
    fun_info():m_arity(0) {}
    fun_info(unsigned arity, list<param_info> const & info, list<unsigned> const & deps):
        m_arity(arity), m_params_info(info), m_deps(deps) {}
    unsigned get_arity() const { return m_arity; }
    list<param_info> const & get_params_info() const { return m_params_info; }
    list<unsigned> const & get_result_dependencies() const { return m_deps; }
};

/** \brief Helper object for retrieving a summary for the parameters
    of a given function or function application.
    We use the summary for quickly detecting which arguments are subsingletons and propositions,
    dependencies, implicit binder info, etc. */
class fun_info_manager {
    type_context &                         m_ctx;
    rb_map<expr, fun_info, expr_quick_cmp> m_fun_info;
    list<unsigned> collect_deps(expr const & e, buffer<expr> const & locals);
public:
    fun_info_manager(type_context & ctx);
    type_context & ctx() { return m_ctx; }
    fun_info get(expr const & fn);
    /** \brief Return information assuming the function has only nargs.
        \pre nargs <= get(fn).get_arity() */
    fun_info get(expr const & fn, unsigned nargs);
    /** \brief Return information for the function application.
        This is more precise than \c get methods for dependent functions.

        Example: given (f : Pi (A : Type), A -> A), \c get_specialization for

                f unit b

        returns a \c fun_info with two param_info
        1) m_specialized = true, m_is_dep = true
        2) m_subsingleton = true, m_deps = {0}

        The second argument is marked as subsingleton only because the resulting information
        is taking into account the first argument.

        \remark \c get and \c get_specialization return the same result for all but
        is_prop and is_subsingleton. */
    fun_info get_specialization(expr const & app);
};
}
