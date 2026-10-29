-- BUZZER: paste this whole file into Supabase > SQL Editor > Run
create table profiles(
 id uuid primary key default gen_random_uuid(),
 name text not null, email text unique not null,
 role text not null default 'user' check (role in ('admin','user')),
 avatar text, points int default 0, streak int default 0,
 best_streak int default 0, last_login date);
create table questions(id serial primary key, category text, question text, options jsonb, answer int, points int default 10);
create table results(
 id bigserial primary key,
 profile_id uuid references profiles on delete cascade,
 question_id int references questions on delete cascade,
 correct boolean, points int default 0, created_at timestamptz default now(),
 unique(profile_id, question_id));
create table alerts(id bigserial primary key, kind text default 'alert', title text, body text, created_at timestamptz default now());
create table logins(profile_id uuid references profiles on delete cascade, day date, primary key(profile_id, day));

-- results -> leaderboard points
create function add_points() returns trigger language plpgsql as $$
begin update profiles set points = points + new.points where id = new.profile_id; return new; end $$;
create trigger results_points after insert on results for each row execute function add_points();

-- daily login streak
create function record_login(p uuid) returns profiles language plpgsql as $$
declare r profiles; s int;
begin
 insert into logins values (p, current_date) on conflict do nothing;
 select * into r from profiles where id = p;
 if r.last_login is distinct from current_date then
  s := case when r.last_login = current_date - 1 then r.streak + 1 else 1 end;
  update profiles set streak = s, best_streak = greatest(best_streak, s), last_login = current_date where id = p;
 end if;
 select * into r from profiles where id = p; return r;
end $$;

create function reset_results() returns void language sql as $$
 delete from results; update profiles set points = 0; $$;

-- demo access (open to anon key; fine for a mock demo, lock down before real use)
alter table profiles enable row level security; alter table questions enable row level security;
alter table results enable row level security; alter table alerts enable row level security; alter table logins enable row level security;
create policy open on profiles for all using (true) with check (true);
create policy open on questions for all using (true) with check (true);
create policy open on results for all using (true) with check (true);
create policy open on alerts for all using (true) with check (true);
create policy open on logins for all using (true) with check (true);
grant execute on function record_login(uuid), reset_results() to anon;

-- realtime
alter publication supabase_realtime add table profiles, results, alerts;

-- 5 mock profiles (2 admin, 3 user)
insert into profiles(name,email,role,avatar,streak,best_streak,last_login) values
('Ava Admin','ava@buzzer.app','admin','🦊',12,12,current_date-1),
('Raj Admin','raj@buzzer.app','admin','🐯',5,9,current_date-1),
('Maya Chen','maya@buzzer.app','user','🐼',8,8,current_date-1),
('Liam Park','liam@buzzer.app','user','🦁',3,6,current_date-1),
('Sofia Diaz','sofia@buzzer.app','user','🐙',1,4,current_date-3);
insert into logins select id, last_login-(g-1) from profiles, generate_series(1,least(streak,7)) g;

-- 10 mock questions
insert into questions(category,question,options,answer,points) values
('Safety','What should you do first when you spot a spill in a walkway?','["Walk around it","Mark it and clean it or report it","Wait for someone else","Take a photo only"]',1,10),
('Safety','How many points of contact should you keep when using a ladder?','["One","Two","Three","None"]',2,10),
('Compliance','Which is the safest way to share a customer password?','["Email it","Never share it","Text it","Post in chat"]',1,10),
('Compliance','A gift from a vendor is worth more than policy allows. You should…','["Keep it quietly","Politely decline and report it","Split it with the team","Sell it"]',1,10),
('Customer Service','A customer is upset. What is the best first step?','["Interrupt with a fix","Listen and acknowledge","Transfer the call","Defend the company"]',1,10),
('Customer Service','What does HEARD stand for in service recovery?','["Hear, Empathize, Apologize, Resolve, Diagnose","Hurry, Escalate, Act, Review, Done","Help, Explain, Ask, Record, Deliver","None of these"]',0,10),
('Security','Which email is most likely phishing?','["Known colleague, normal topic","Urgent link asking you to verify your login","Team calendar invite","Newsletter you subscribed to"]',1,10),
('Security','What makes a strong password?','["Your birthday","Short and simple","Long passphrase with mixed characters","Same everywhere"]',2,10),
('Wellness','How often should you take a short break from screen work?','["Every 20 minutes (look away briefly)","Once a day","Never","Only at lunch"]',0,10),
('Product Knowledge','Why is spaced repetition effective for learning?','["It crams everything at once","It revisits ideas over time to build memory","It skips review","It avoids quizzes"]',1,10);

-- starting scores so the leaderboard isn't empty
insert into results(profile_id,question_id,correct,points)
 select p.id,q.id,true,10 from profiles p, questions q where p.name='Maya Chen' and q.id<=6;
insert into results(profile_id,question_id,correct,points)
 select p.id,q.id,true,10 from profiles p, questions q where p.name='Liam Park' and q.id<=4;
insert into results(profile_id,question_id,correct,points)
 select p.id,q.id,true,10 from profiles p, questions q where p.name='Sofia Diaz' and q.id<=2;

insert into alerts(kind,title,body) values
('reminder','Daily 3-minute training','Answer today''s questions to keep your streak alive.'),
('alert','New safety policy','Please review the updated ladder safety guidance this week.');
