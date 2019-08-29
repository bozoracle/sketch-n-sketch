open Lang

val empty : constraints
val from_hole_filling : hole_filling -> constraints
val from_unsolved_constraints : unsolved_constraints -> constraints

val solved_singleton : hole_name -> exp -> constraints
val unsolved_singleton : hole_name -> worlds -> constraints

val merge_solved : hole_filling list -> hole_filling option
val merge_unsolved : unsolved_constraints list -> unsolved_constraints
val merge : constraints list -> constraints option