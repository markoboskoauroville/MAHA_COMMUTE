import zipfile, sys, datetime, io
def make(path, x_runs_today, variant="v1"):
    t = datetime.date.today(); y = t - datetime.timedelta(days=1)
    f = lambda d: d.strftime("%Y%m%d")
    rows = ["100,Glavni kolodvor,45.8050,15.9800,0",
            "101,Branimirova,45.8055,15.9810,0",
            "200,Samo radnim danom,45.8060,15.9790,0",
            "300,Nocna linija,45.8070,15.9820,",
            "900,Parent station,45.8052,15.9805,1"]
    if variant == "v2":     # a later feed: 101 renamed, 100 moved 50 m north, 400 is new
        rows = [r.replace("101,Branimirova", "101,Branimirova ulica").replace("45.8050,15.9800,0", "45.80545,15.9800,0")
                for r in rows] + ["400,Nova stanica,45.8080,15.9830,0"]
    if variant == "v3":     # a feed that no longer lists 200
        rows = [r for r in rows if not r.startswith("200,")]
    stops = "stop_id,stop_name,stop_lat,stop_lon,location_type\n" + "\n".join(rows)
    routes = "route_id,route_short_name,route_long_name\n6,6,Sljeme\n31,31,Nocna"
    trips = "route_id,service_id,trip_id,trip_headsign\n6,DAILY,t1,Sljeme\n6,SPECIAL,t2,Sljeme\n31,NIGHT,t3,Nocna"
    st = ["trip_id,arrival_time,departure_time,stop_id,stop_sequence",
          "t1,08:00:00,08:00:00,100,1","t1,08:05:00,08:05:00,101,2",
          "t2,09:00:00,09:00:00,200,1","t2,09:05:00,09:05:00,100,2",
          "t3,24:10:00,24:10:00,300,1","t3,24:15:00,24:15:00,100,2"]
    cd = ["service_id,date,exception_type", "DAILY,%s,1"%f(t)]
    if x_runs_today: cd.append("SPECIAL,%s,1"%f(t))
    # the night service ran yesterday only (a 24:10 ride that belongs to yesterday)
    cd.append("NIGHT,%s,1"%f(y))
    with zipfile.ZipFile(path,"w") as z:
        z.writestr("stops.txt",stops); z.writestr("routes.txt",routes)
        z.writestr("trips.txt",trips); z.writestr("stop_times.txt","\n".join(st)+"\n")
        z.writestr("calendar_dates.txt","\n".join(cd)+"\n")
if __name__=="__main__": make(sys.argv[1], sys.argv[2]=="1", sys.argv[3] if len(sys.argv) > 3 else "v1")
