task initialize = fn () => FeedFfi.init

con pattern internal output = {Initial : internal,
                               EnterTag : {Tag : string, Attrs : list (string * string), Cdata : option string} -> internal -> option internal,
                               ExitTag : internal -> option internal,
                               Finished : internal -> option (output * bool)}

val null : pattern unit (variant []) =
    {Initial = (),
     EnterTag = fn _ () => Some (),
     ExitTag = fn () => Some (),
     Finished = fn () => None}

con tagInternal (attrs :: {Unit}) = option {Attrs : $(mapU string attrs), Cdata : option string}

fun tagG [attrs ::: {Unit}] [t ::: Type] (fl : folder attrs) (accept : {Attrs : $(mapU string attrs), Cdata : option string} -> option t)
         (name : string) (attrs : $(mapU string attrs))
    : pattern (tagInternal attrs) t =
    {Initial = None,
     EnterTag = fn tinfo _ =>
                   if tinfo.Tag <> name then
                       None
                   else
                       case @foldUR [string] [fn r => option $(mapU string r)]
                             (fn [nm ::_] [r ::_] [[nm] ~ r] aname ro =>
                                 case ro of
                                     None => None
                                   | Some r =>
                                     case List.assoc aname tinfo.Attrs of
                                         None => None
                                       | Some v => Some ({nm = v} ++ r))
                             (Some {}) fl attrs of
                           None => None
                         | Some vs =>
                           let
                               val v = {Attrs = vs, Cdata = tinfo.Cdata}
                           in
                               case accept v of
                                   None => None
                                 | Some _ => Some (Some v)
                           end,
     ExitTag = fn _ => None,
     Finished = fn state => case state of
                                None => None
                              | Some state =>
                                case accept state of
                                    None => None
                                  | Some v => Some (v, False)}

fun tag [attrs ::: {Unit}] (fl : folder attrs) (name : string) (attrs : $(mapU string attrs))
    : pattern (tagInternal attrs) {Attrs : $(mapU string attrs), Cdata : option string} =
    @tagG fl Some name attrs

fun tagA [attrs ::: {Unit}] (fl : folder attrs) (name : string) (attrs : $(mapU string attrs))
    : pattern (tagInternal attrs) $(mapU string attrs) =
    @tagG fl (fn r => Some r.Attrs) name attrs

fun tagC (name : string) : pattern (tagInternal []) string =
    tagG (fn r => r.Cdata) name {}

datatype status a = Initial | Pending of a | Matched of a

con childrenInternal (parent :: Type) (children :: {Type}) = option (parent * int * $(map status children))

fun children [parentI ::: Type] [parent ::: Type] [children ::: {(Type * Type)}]
             (parent : pattern parentI parent) (children : $(map (fn (i, d) => pattern i d) children)) (fl : folder children)
    : pattern (childrenInternal parentI (map fst children)) (parent * $(map snd children)) =
      {Initial = None,
       EnterTag = fn tinfo state =>
                     case state of
                         None =>
                         (case parent.EnterTag tinfo parent.Initial of
                              None => None
                            | Some pstate => Some (Some (pstate, 1, @map0 [status] (fn [t ::_] => Initial)
                                                                     (@@Folder.mp [fst] [_] fl))))
                       | Some (pstate, depth, cstates) =>
                         Some (Some (pstate,
                                     depth+1,
                                     @map2 [fn (i, d) => pattern i d] [fn (i, d) => status i] [fn (i, d) => status i]
                                      (fn [p] (ch : pattern p.1 p.2) (cstate : status p.1) =>
                                          case cstate of
                                              Initial =>
                                              (case ch.EnterTag tinfo ch.Initial of
                                                   None => Initial
                                                 | Some v =>
                                                   case ch.Finished v of
                                                       None => Pending v
                                                     | _ => Matched v)
                                            | Pending cstate =>
                                              (case ch.EnterTag tinfo cstate of
                                                   None => Initial
                                                 | Some v =>
                                                   case ch.Finished v of
                                                       None => Pending v
                                                     | _ => Matched v)
                                            | v => v)
                                      fl children cstates)),
       ExitTag = fn state =>
                    case state of
                        None => None
                      | Some (pstate, 1, cstates) =>
                        (case parent.ExitTag pstate of
                             None => None
                           | Some pstate => Some (Some (pstate, 0, cstates)))
                      | Some (pstate, depth, cstates) =>
                        Some (Some (pstate, depth-1,
                                    @map2 [fn (i, d) => pattern i d] [fn (i, d) => status i] [fn (i, d) => status i]
                                     (fn [p] (ch : pattern p.1 p.2) (cstate : status p.1) =>
                                         case cstate of
                                             Pending cstate =>
                                             (case ch.ExitTag cstate of
                                                  None => Initial
                                                | Some cstate' =>
                                                  case ch.Finished cstate' of
                                                      None => Pending cstate'
                                                    | _ => Matched cstate')
                                           | _ => cstate)
                              fl children cstates)),
       Finished = fn state =>
                     case state of
                         Some (pstate, _, cstates) =>
                         (case parent.Finished pstate of
                              None => None
                            | Some (pdata, pcont) =>
                              case @foldR2 [fn (i, d) => pattern i d] [fn (i, d) => status i] [fn cs => option $(map snd cs)]
                                    (fn [nm ::_] [p ::_] [r ::_] [[nm] ~ r] (ch : pattern p.1 p.2) (cstate : status p.1) acc =>
                                        case acc of
                                            None => None
                                          | Some acc =>
                                            case cstate of
                                                Matched cstate =>
                                                (case ch.Finished cstate of
                                                     None => None
                                                   | Some (cdata, _) => Some ({nm = cdata} ++ acc))
                                              | _ => None)
                                    (Some {}) fl children cstates of
                                  None => None
                                | Some cdata => Some ((pdata, cdata), pcont))
                       | _ => None}

con treeInternal (parent :: Type) (child :: Type) = option (parent * int * option child)

fun tree [parentI ::: Type] [parent ::: Type] [childI ::: Type] [child ::: Type]
    (parent : pattern parentI parent) (child : pattern childI child)
    : pattern (treeInternal parentI childI) (parent * child) =
    {Initial = None,
     EnterTag = fn tinfo state =>
                   case state of
                       None =>
                       (case parent.EnterTag tinfo parent.Initial of
                            None => None
                          | Some pstate => Some (Some (pstate, 1, None)))
                     | Some (pstate, depth, cstate) =>
                       Some (Some (pstate,
                                   depth+1,
                                   child.EnterTag tinfo (Option.get child.Initial cstate))),
     ExitTag = fn state =>
                  case state of
                      None => None
                    | Some (pstate, 1, cstate) =>
                      (case parent.ExitTag pstate of
                           None => None
                         | Some pstate => Some (Some (pstate, 0, cstate)))
                    | Some (pstate, depth, cstate) =>
                      Some (Some (pstate, depth-1, Option.bind child.ExitTag cstate)),
     Finished = fn state =>
                   case state of
                       None => None
                     | Some (pstate, _, cstate) =>
                       case parent.Finished pstate of
                           None => None
                         | Some (pdata, _) =>
                           case cstate of
                               None => None
                             | Some cstate =>
                               case child.Finished cstate of
                                   None => None
                                 | Some (cdata, _) => Some ((pdata, cdata), True)}

fun app [internal ::: Type] [data ::: Type] (p : pattern internal data) (f : data -> transaction {}) (url : string) : transaction {} =
    let
        fun recur xml state =
            case String.seek xml #"<" of
                None => return ()
              | Some xml =>
                if xml <> "" && String.sub xml 0 = #"/" then
                    case String.seek xml #"\x3E" of
                        None => return ()
                      | Some xml =>
                        case p.ExitTag state of
                            None => recur xml p.Initial
                          | Some state =>
                            case p.Finished state of
                                 None => recur xml state
                               | Some (data, cont) =>
                                 f data;
                                 recur xml (if cont then state else p.Initial)
                else if xml <> "" && String.sub xml 0 = #"?" then
                    case String.seek xml #"\x3E" of
                        None => return ()
                      | Some xml => recur xml state
                else if xml <> "" && String.sub xml 0 = #"!" then
                    if String.lengthGe xml 3 && String.sub xml 1 = #"-" && String.sub xml 2 = #"-" then
                        let
                            fun skipper xml =
                                case String.seek xml #"-" of
                                    None => xml
                                  | Some xml =>
                                    if String.lengthGe xml 2 && String.sub xml 0 = #"-" && String.sub xml 1 = #"\x3E" then
                                        String.suffix xml 2
                                    else
                                        skipper xml
                        in
                            recur (skipper (String.suffix xml 3)) state
                        end
                    else
                        case String.seek xml #"]" of
                            None => return ()
                          | Some xml =>
                            case String.seek xml #"\x3E" of
                                None => return ()
                              | Some xml => recur xml state
                else
                    case String.msplit {Needle = " >/", Haystack = xml} of
                        None => return ()
                      | Some (tagName, ch, xml) =>
                        let
                            fun readAttrs ch xml acc =
                                case ch of
                                    #"\x3E" => (xml, acc, False)
                                  | #"/" =>
                                    (case String.seek xml #"\x3E" of
                                         None => (xml, acc, True)
                                       | Some xml => (xml, acc, True))
                                  | _ =>
                                    if String.lengthGe xml 2 && Char.isSpace (String.sub xml 0) then
                                        readAttrs (String.sub xml 0) (String.suffix xml 1) acc
                                    else if xml <> "" && String.sub xml 0 = #"\x3E" then
                                        (String.suffix xml 1, acc, False)
                                    else if xml <> "" && String.sub xml 0 = #"/" then
                                        (case String.seek xml #"\x3E" of
                                             None => (xml, acc, True)
                                           | Some xml => (xml, acc, True))
                                    else
                                        case String.split xml #"=" of
                                            None => (xml, acc, False)
                                          | Some (aname, xml) =>
                                            if xml = "" || String.sub xml 0 <> #"\"" then
                                                (xml, (aname, "") :: acc, False)
                                            else
                                                case String.split (String.suffix xml 1) #"\"" of
                                                    None => (xml, (aname, "") :: acc, False)
                                                  | Some (value, xml) =>
                                                    if xml = "" then
                                                        (xml, (aname, value) :: acc, False)
                                                    else
                                                        readAttrs (String.sub xml 0) (String.suffix xml 1) ((aname, value) :: acc)

                            val (xml, attrs, ended) = readAttrs ch xml []

                            fun skipSpaces xml =
                                if xml <> "" && Char.isSpace (String.sub xml 0) then
                                    skipSpaces (String.suffix xml 1)
                                else
                                    xml

                            val xml = skipSpaces xml

                            val (xml, cdata) =
                                if ended then
                                    (xml, None)
                                else if String.isPrefix {Prefix = "<![CDATA[", Full = xml} then
                                    let
                                        fun skipper xml acc =
                                            case String.split xml #"]" of
                                                None => (acc ^ xml, None)
                                              | Some (pre, xml) =>
                                                if String.lengthGe xml 2 && String.sub xml 0 = #"]" && String.sub xml 1 = #"\x3E" then
                                                    (String.suffix xml 2, Some (acc ^ pre))
                                                else
                                                    skipper xml (acc ^ "]" ^ pre)
                                    in
                                        skipper (String.suffix xml 9) ""
                                    end
                                else
                                    case String.split' xml #"<" of
                                        None => (xml, None)
                                      | Some (cdata, xml) => (xml, Some cdata)
                        in
                            case p.EnterTag {Tag = tagName, Attrs = attrs, Cdata = cdata} state of
                                None => recur xml p.Initial
                              | Some state =>
                                case p.Finished state of
                                     None =>
                                     (case (if ended then p.ExitTag state else Some state) of
                                          None => recur xml p.Initial
                                        | Some state =>
                                          case p.Finished state of
                                              None => recur xml state
                                            | Some (data, cont) =>
                                              f data;
                                              recur xml (if cont then state else p.Initial))
                                   | Some (data, cont) =>
                                     f data;
                                     recur xml (if cont then state else p.Initial)
                        end
    in
        xml <- FeedFfi.fetch url;
        recur xml p.Initial
    end