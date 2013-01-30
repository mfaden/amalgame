:-module(ag_opm, [
		  opm_was_generated_by/4,       % +Process (cause), +Artifact (effect), +RDFGraph, +Options
		  opm_include_dependency/2,     % +SourceGraph, +TargetGraph
		  opm_clear_process/1,           % +Process (bnode)
		  opm_assert_artefact_version/3,
		  clear_prov_cache/0,
		  current_program_uri/2
		 ]).

/* <module> OPM -- simple support for the OPM Provenance Model (OPM)

@see http://openprovenance.org/

*/

:- use_module(library(http/http_host)).
:- use_module(library(http/http_session)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(version)).
:- use_module(library(prov_schema)).
:- use_module(user(user_db)).

:- dynamic
	current_program_uri/2.

clear_prov_cache :-
	retractall(current_program_uri(_,_)).

opm_include_dependency(Graph, Target) :-
	opm_include_dependency([Graph], [], DepList),
	expand_deplist(DepList, [], Results),
	rdf_assert_list(Results, Target).

rdf_assert_list([], _).
rdf_assert_list([rdf(S,P,O)|T], Graph) :-
	rdf_assert(S,P,O,Graph),
	rdf_assert_list(T, Graph).

opm_include_dependency([], Results, Results).

opm_include_dependency([H|T], Accum, Results) :-
	opm_include_dependency(T, Accum, TailResults),
	findall(Dep, dependent(H, Dep),Deps),
	opm_include_dependency(Deps, [H], HeadResults),
	append(TailResults, HeadResults, Results).

dependent(S, Dep) :- rdf(S, prov:wasDerivedFrom, Dep).
dependent(S, Dep) :- rdf(S, prov:wasGeneratedBy, Dep).
dependent(S, Dep) :-
	rdfs_individual_of(S, prov:'Activity'),
	rdf(S,_,Dep),
	rdf_is_bnode(Dep).

expand_deplist([], Results, Results).
expand_deplist([H|T], Accum, Results) :-
	findall(Triple, opm_triple(H,Triple), Triples),
	append(Triples, Accum, NewAccum),
	expand_deplist(T, NewAccum, Results).

:- rdf_meta
	opm_triple(r, t).

opm_triple(S, rdf(S, owl:versionInfo,O))     :- rdf(S, owl:versionInfo, O).
opm_triple(S, rdf(S, prov:wasDerivedFrom,O)) :- rdf(S, prov:wasDerivedFrom, O).
opm_triple(S, rdf(S, prov:wasGeneratedBy,O)) :- rdf(S, prov:wasGeneratedBy, O).
opm_triple(S, rdf(S,P,O)) :-
	rdfs_individual_of(S, prov:'Activity'),
	rdf(S,P,O).
opm_triple(S, rdf(S,P,O)) :-
	rdf_is_bnode(S),
	(   rdfs_individual_of(S, align:'Cell') -> gtrace; true),
	rdf(S,P,O).

%%     opm_was_generated_by(+Process, +Artifacts, +Graph, +Options) is
%%     det.
%
%	Assert OPM provenance information about Artifacts generated by
%	Process into named Graph (all three are URLs).
%	Options is a list of options, currently implemented options
%	include:
%
%	* was_derived_from([Sources]) to indicate the artifacts were
%	derived from the given list of source artifacts
%	* request(Request) to record information about the request URI
%	used in the web service to create Artifacts.

opm_was_generated_by(_, [], _, _) :- !.
opm_was_generated_by(Process, Artifacts, Graph, Options) :-
	is_list(Artifacts),!,
	rdf_assert(Process, rdf:type, prov:'Activity',	Graph),
	forall(member(Artifact, Artifacts),
	       (   rdf_assert(Artifact, rdf:type, prov:'Entity',    Graph),
		   rdf_assert(Artifact, prov:wasGeneratedBy, Process, Graph)
	       )
	      ),
	opm_program(Graph, Program),
	opm_agent(Graph, Agent),
	get_time(Now),
	get_xml_dateTime(Now, NowXML),
	rdf_bnode(BN_now),
	rdf_assert(BN_now, rdf:type, time:'Instant',  Graph),
	rdf_assert(BN_now, time:inXSDDateTime, literal(type(xsd:dateTime, NowXML)), Graph),
	rdf_assert(Process, prov:endedAtTime,   BN_now , Graph),
	rdf_assert(Process, prov:wasAssociatedWith, Program, Graph),
	rdf_assert(Process, prov:wasAssociatedWith, Agent,   Graph),

	(   memberchk(was_derived_from(Sources), Options)
	->  forall(member(Source, Sources),
		   (   forall(member(Artifact, Artifacts),
			     rdf_assert(Artifact, prov:wasDerivedFrom,  Source,  Graph)
			     ),
		       rdf_assert(Process, prov:used, Source, Graph),
		       (   \+ rdfs_individual_of(Source, prov:'Entity')
		       ->  rdf_assert(Source, rdf:type,	prov:'Entity', Graph)
		       ;   true
		       )
		   )
		  )
	;   true
	),
	(   memberchk(request(Request), Options)
	->  http_current_host(Request, Hostname, Port, [global(true)]),
	    memberchk(request_uri(ReqURI), Request),
	    memberchk(protocol(Protocol), Request),
	    format(atom(ReqUsed), '~w://~w:~w~w', [Protocol,Hostname,Port,ReqURI]),
	    rdf_assert(Process, amalgame:request, ReqUsed, Graph)
	;   true
	),
	true.

opm_was_generated_by(Process, Artifact, Graph, Options) :-
	atom(Artifact),!,
	opm_was_generated_by(Process, [Artifact], Graph, Options).

opm_clear_process(Process) :-
	rdf_retractall(Process, _, _, _),
	rdf_retractall(_, _, Process, _).

opm_program(Graph, Program) :-
	current_program_uri(Graph, Program),!.

opm_program(Graph, Program)  :-
	rdf_bnode(Program),
	assert(current_program_uri(Graph, Program)),
	rdf_assert(Program, rdfs:label, literal('Amalgame alignment platform'), Graph),
	rdf_assert(Program, rdf:type,   prov:'SoftwareAgent', Graph),

	(  current_prolog_flag(version_git, PL_version)
	-> true
	;   current_prolog_flag(version, PL_version)
	),
	findall(M-U-V,
		(   git_module_property(M, home_url(U)),
		    git_module_property(M, version(V))
		),
		MUVs
	       ),
	Prolog = 'swi-prolog'-'http://www.swi-prolog.org'-PL_version,
	forall(member(M-U-V, [Prolog|MUVs]),
	       (   rdf_bnode(B),
	           rdf_assert(Program, amalgame:component, B, Graph),
		   rdf_assert(B, 'http://usefulinc.com/ns/doap#revision',
			      literal(V), Graph),
		   rdf_assert(B, 'http://usefulinc.com/ns/doap#name',
			      literal(M), Graph),
		   rdf_assert(B, rdfs:seeAlso,
			      literal(U), Graph)
	       )
	      ),
	!.

opm_agent(Graph, Agent) :-
	(
	http_in_session(_)
	->
	   logged_on(User, anonymous),
	   user_property(User, url(Agent)),
	   (   user_property(User, realname(UserName))
	   ->  true
	   ;   user_property(User, openid(UserName))
	   ->  true
	   ;   UserName = Agent
	   )
	;
	 rdf_bnode(Agent),
	 UserName = 'anonymous user (not logged in)'
	),

	rdf_assert(Agent, rdfs:label, literal(UserName),  Graph),
	rdf_assert(Agent, rdf:type,   prov:'Agent',	  Graph).

get_xml_dateTime(T, TimeStamp) :-
	format_time(atom(TimeStamp), '%Y-%m-%dT%H-%M-%S%Oz', T).

%%	opm_assert_artefact_version(+Artifact,+SourceGraph,+TargetGraph) is semidet.
%
%	Assert (git) version information about Artifact into the named
%	graph TargetGraph. SourceGraph is the main named graph in which
%	Artifact is defined.

opm_assert_artefact_version(Artifact, SourceGraph, TargetGraph) :-
	rdf_graph_property(SourceGraph, source(SourceFileURL)),
	uri_file_name(SourceFileURL, Filename),
	file_directory_name(Filename, Dirname),
	register_git_module(Artifact, [directory(Dirname), home_url(Artifact)]),
	(   git_module_property(Artifact, version(Version))
	->  format(atom(VersionS),  'GIT version: ~w', [Version]),
	    rdf_assert(Artifact, owl:versionInfo, literal(VersionS), TargetGraph)
	;   (rdf_graph_property(SourceGraph, hash(Hash)),
	     rdf_graph_property(SourceGraph, source_last_modified(LastModified)),
	     format_time(atom(Mod), 'Last-Modified: %Y-%m-%dT%H-%M-%S%Oz', LastModified),
	     rdf_assert(Artifact, owl:versionInfo, literal(Mod), TargetGraph),
	     rdf_assert(Artifact, owl:versionInfo, literal(Hash), TargetGraph)
	    )
	).
