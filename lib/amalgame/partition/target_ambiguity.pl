:- module(target_ambiguity,[]).

:- use_module(library(semweb/rdf_db)).

:- public partition/3.
:- multifile amalgame:component/2.

amalgame:component(partition, target_ambiguity(alignment_graph, [alignment_graph], [])).

%%	partition(+Input, -Output, +Options)
%
%	Output a list of graphs where the first element contains
%	all ambiguous alignments and the second the unambiguous
%	ones.
%       Input is a sorted list of alignment terms.

partition(AlignmentGraph, ListOfGraphs, _Options) :-
	ListOfGraphs = [ambiguous(A1),
			unambiguous(A2)
		      ],
	partition_(AlignmentGraph, A1, A2).

partition_([], [], []).
partition_([align(S,T,P)|As], A1, A2) :-
	same_source(As, S, Same, Rest),
	(   Same = []
	->  A2 = [align(S,T,P)|A2Rest],
	    A1 = A1Rest
	;   append([align(S,T,P)|Same], A1Rest, A1),
	    A2 = A2Rest
	),
	partition_(Rest, A1Rest, A2Rest).

same_source([align(S,T,P)|As], S, [align(S,T,P)|Same], Rest) :-
	!,
	same_source(As, S, Same, Rest).
same_source(As, _S, [], As).
